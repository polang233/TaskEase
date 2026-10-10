import AppKit
import Foundation
import Darwin

/// 在主 actor 上复制 AppKit 应用信息，再传递给采样 actor。
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
    var networkStatus: NetworkMonitorStatus = .disabled
}

/// 串行持有采样基线和路径缓存，扫描工作在主 actor 之外执行。
actor ProcessMonitor {
    private var displaySampler = ProcessSampler()
    private var controlSampler = ProcessSampler()
    private let networkMonitor = NetworkMonitor()
    private var networkSampler = NetworkRateSampler()

    func sample(_ applications: [RunningApplication], includeSystem: Bool, includeNetwork: Bool = false) async -> MonitoringSnapshot {
        // 显示与控制各用一份基线，网络快照只为可见数据面板读取。
        guard includeSystem else { return controlSampler.sample(applications, includeSystem: false) }
        let snapshot = displaySampler.sample(applications, includeSystem: true)
        guard includeNetwork else {
            networkSampler.reset()
            return snapshot
        }
        let identities = Dictionary(uniqueKeysWithValues: snapshot.apps.flatMap { $0.samples }.map { ($0.identity.pid, $0.identity) })
        guard let counters = await networkMonitor.sample(pids: Set(identities.keys)) else {
            networkSampler.reset()
            return MonitoringSnapshot(apps: snapshot.apps, system: snapshot.system,
                networkStatus: .unavailable("暂时无法读取网络统计"))
        }
        // nettop 输出仅用 PID 标识，完成后再次验证启动时间，排除读取期间的 PID 复用。
        let verified = counters.filter { pid, _ in
            identities[pid].map { NativeProcess.identity(pid) == $0 } == true
        }
        let readings = networkSampler.sample(snapshot.apps, counters: verified, now: NativeProcess.now)
        var apps = snapshot.apps
        for index in apps.indices {
            apps[index].network = readings.applications[apps[index].id]
            apps[index].processNetwork = readings.processes.filter { identity, _ in
                apps[index].samples.contains { $0.identity == identity }
            }
        }
        return MonitoringSnapshot(apps: apps, system: snapshot.system, networkStatus: .available)
    }

    func cancelNetworkSampling() async {
        await networkMonitor.cancel()
        networkSampler.reset()
    }

}

/// 采样状态为值类型，同样供命令行自检同步调用。
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
        // 长时间空闲后重建基线，下一次采样前 CPU 暂无可比较数值。
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
            // 已知成员重新核对可执行路径，避免 exec 换程序后继续沿用旧归属。
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
        // GPU 驱动数据表示整机估计值，只为可见数据面板读取。
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
