import AppKit
import Foundation
import Darwin

/// Copy workspace objects into values before sampling away from the main actor.
struct RunningApplication: Sendable {
    let id: String
    let name: String
    let roots: [String]
    let primaryPIDs: Set<Int32>
    let isHidden: Bool

    var isSystemApp: Bool {
        ApplicationScope.isSystem(id: id, roots: roots)
    }

    @MainActor static func capture(showSystemApps: Bool, only ids: Set<String>? = nil) -> [RunningApplication] {
        let ownID = Bundle.main.bundleIdentifier
        let running = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.bundleIdentifier != nil && $0.bundleURL != nil &&
            $0.bundleIdentifier != ownID && $0.activationPolicy != .prohibited &&
            !($0.bundleURL?.path.contains(".app/Contents/") ?? false)
        }
        return Dictionary(grouping: running, by: { $0.bundleIdentifier ?? "" }).compactMap { id, instances in
            if let ids, !ids.contains(id) { return nil }
            guard let first = instances.first else { return nil }
            let app = RunningApplication(id: id, name: first.localizedName ?? id,
                                         roots: Array(Set(instances.compactMap { $0.bundleURL?.resolvingSymlinksInPath().path })).sorted(),
                                         primaryPIDs: Set(instances.map(\.processIdentifier)),
                                         isHidden: instances.allSatisfy(\.isHidden))
            return !showSystemApps && app.isSystemApp ? nil : app
        }
    }
}

struct MonitoringSnapshot: Sendable {
    let apps: [AppReading]
    let system: SystemReading?
}

/// The actor owns the sampler's previous counters and path cache. No UI callback
/// performs the libproc scan, and overlapping refresh requests cannot race its state.
actor ProcessMonitor {
    private var displaySampler = ProcessSampler()
    private var controlSampler = ProcessSampler()

    func sample(_ applications: [RunningApplication], includeSystem: Bool) -> MonitoringSnapshot {
        // Separate baselines keep infrequent display samples complete while controls
        // refresh only their selected process groups.
        if includeSystem { return displaySampler.sample(applications, includeSystem: true) }
        return controlSampler.sample(applications, includeSystem: false)
    }

}

/// Value state also allows the command-line self-check to sample synchronously.
struct ProcessSampler {
    private var previous: [ProcessIdentity: ProcessSample] = [:]
    private var previousWall: UInt64?
    private var previousCPU: TECPUTicks?
    private var paths: [ProcessIdentity: String] = [:]
    private var pathCacheTime: UInt64 = 0
    private var lastGPUTime: UInt64 = 0
    private var cachedGPU: Double?

    mutating func reset() {
        previous.removeAll()
        previousWall = nil
        previousCPU = nil
    }

    mutating func sample(_ applications: [RunningApplication], includeSystem: Bool) -> MonitoringSnapshot {
        let now = NativeProcess.now
        if applications.isEmpty && !includeSystem {
            reset()
            return MonitoringSnapshot(apps: [], system: nil)
        }
        // A long idle gap starts a fresh baseline; CPU stays unavailable until the next sample.
        if let previousWall, NativeProcess.seconds(since: previousWall) > 20 { reset() }
        if pathCacheTime == 0 || NativeProcess.seconds(since: pathCacheTime) >= 30 {
            paths.removeAll()
            pathCacheTime = now
        }
        let elapsed = previousWall.map { Double(now &- $0) }
        var apps: [String: AppReading] = [:]
        var primaryOwners: [Int32: String] = [:]
        for app in applications {
            apps[app.id] = AppReading(id: app.id, name: app.name, bundlePaths: app.roots,
                                     primaryPIDs: app.primaryPIDs, targets: [], samples: [],
                                     cpuPercent: elapsed == nil ? nil : 0, memoryBytes: 0,
                                     readRate: 0, writeRate: 0, canControl: !app.isSystemApp && !app.id.hasPrefix("com.apple."),
                                     isHidden: app.isHidden)
            for pid in app.primaryPIDs { primaryOwners[pid] = app.id }
        }
        var next: [ProcessIdentity: ProcessSample] = [:]
        var nextPaths: [ProcessIdentity: String] = [:]
        var comparable: Set<String> = []
        for pid in NativeProcess.pids() {
            guard let identity = NativeProcess.identity(pid), identity.uid == geteuid() else { continue }
            // Recheck known members on every sample; a process can exec a new image.
            let executablePath = previous[identity] == nil ? paths[identity] ?? NativeProcess.path(pid) : NativeProcess.path(pid)
            guard let executable = executablePath else { continue }
            nextPaths[identity] = executable
            let owner = primaryOwners[pid] ?? applications.first {
                $0.roots.contains { executable.hasPrefix($0 + "/Contents/") }
            }?.id
            guard let id = owner, let reading = NativeProcess.sample(pid), reading.identity == identity else { continue }
            next[identity] = reading
            apps[id]?.samples.append(reading)
            apps[id]?.memoryBytes += reading.memoryBytes
            if let root = apps[id]?.bundlePaths.first(where: { executable.hasPrefix($0 + "/Contents/") }) {
                apps[id]?.targets.append(ControlTarget(identity: identity, executablePath: executable, bundlePath: root))
            }
            if let elapsed, elapsed > 0, let old = previous[identity] {
                comparable.insert(id)
                apps[id]?.cpuPercent? += 100 * Double(reading.cpuTicks >= old.cpuTicks ? reading.cpuTicks - old.cpuTicks : 0) / elapsed
                let seconds = elapsed / NativeProcess.ticksPerSecond
                apps[id]?.readRate += Double(reading.readBytes >= old.readBytes ? reading.readBytes - old.readBytes : 0) / seconds
                apps[id]?.writeRate += Double(reading.writeBytes >= old.writeBytes ? reading.writeBytes - old.writeBytes : 0) / seconds
                apps[id]?.wakeupRate += Double(reading.wakeups >= old.wakeups ? reading.wakeups - old.wakeups : 0) / seconds
            }
        }
        for id in Array(apps.keys) {
            if !comparable.contains(id) { apps[id]?.cpuPercent = nil }
            if apps[id]?.samples.isEmpty == true { apps[id]?.canControl = false }
        }
        previous = next
        previousWall = now
        paths = nextPaths
        let system = includeSystem ? sampleSystem(now: now) : nil
        let sorted = apps.values.sorted {
            if $0.cpuPercent == $1.cpuPercent { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return ($0.cpuPercent ?? -1) > ($1.cpuPercent ?? -1)
        }
        return MonitoringSnapshot(apps: sorted, system: system)
    }

    private mutating func sampleSystem(now: UInt64) -> SystemReading {
        var system = SystemReading()
        var ticks = TECPUTicks()
        if te_cpu_ticks(&ticks) != 0 {
            if let old = previousCPU {
                let current = [ticks.user, ticks.system, ticks.idle, ticks.nice]
                let before = [old.user, old.system, old.idle, old.nice]
                let deltas = zip(current, before).map { $0 >= $1 ? $0 - $1 : 0 }
                let total = deltas.reduce(0, +)
                if total > 0 { system.cpuPercent = 100 * Double(total - deltas[2]) / Double(total) }
            }
            previousCPU = ticks
        }
        // The driver statistic is a whole-device estimate. Read it only for visible UI.
        if lastGPUTime == 0 || Double(now &- lastGPUTime) / NativeProcess.ticksPerSecond >= 4 {
            let raw = te_gpu_percent()
            cachedGPU = raw >= 0 ? raw : nil
            lastGPUTime = now
        }
        system.gpuPercent = cachedGPU
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: system.thermalLabel = "正常"
        case .fair: system.thermalLabel = "轻度升温"
        case .serious: system.thermalLabel = "较高"
        case .critical: system.thermalLabel = "严重"
        @unknown default: system.thermalLabel = "未知"
        }
        return system
    }
}
