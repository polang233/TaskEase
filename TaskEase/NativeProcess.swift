import Foundation
import AppKit
import Darwin
import IOKit

enum NativeProcess {
    static var ticksPerSecond: Double { te_ticks_per_second() }
    static var now: UInt64 { te_now() }
    static func seconds(since ticks: UInt64) -> Double { Double(now &- ticks) / ticksPerSecond }
    static func identity(_ pid: Int32) -> ProcessIdentity? {
        var raw = TEProcessStats()
        guard te_process_identity(pid, &raw) != 0 else { return nil }
        return ProcessIdentity(pid: raw.pid, uid: raw.uid,
                               startSeconds: raw.startSeconds, startMicroseconds: raw.startMicroseconds)
    }
    static func sample(_ pid: Int32) -> ProcessSample? {
        var raw = TEProcessStats()
        guard te_process_stats(pid, &raw) != 0 else { return nil }
        return ProcessSample(identity: ProcessIdentity(pid: raw.pid, uid: raw.uid,
                             startSeconds: raw.startSeconds, startMicroseconds: raw.startMicroseconds),
                             parentPID: raw.parentPid, status: raw.status, cpuTicks: raw.cpuTicks,
                             memoryBytes: raw.physicalBytes, readBytes: raw.diskReadBytes,
                             writeBytes: raw.diskWriteBytes, wakeups: raw.interruptWakeups)
    }
    static func path(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard te_process_path(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath().path
    }
    static func pids() -> [Int32] {
        var buffer = [Int32](repeating: 0, count: 8192)
        let count = te_list_pids(&buffer, Int32(buffer.count * MemoryLayout<Int32>.stride))
        return count > 0 ? Array(buffer.prefix(Int(count))) : []
    }
    static func matches(_ target: ControlTarget) -> Bool {
        guard target.identity.pid > 1, target.identity.uid == geteuid(),
              let current = identity(target.identity.pid), current == target.identity,
              let executable = path(current.pid), executable == target.executablePath else { return false }
        let root = URL(fileURLWithPath: target.bundlePath).resolvingSymlinksInPath().path
        return root.hasSuffix(".app") && !root.hasPrefix("/System/") &&
            executable.hasPrefix(root + "/Contents/")
    }
    @discardableResult static func background(_ target: ControlTarget, enabled: Bool) -> Bool {
        guard enabled ? matches(target) : identity(target.identity.pid) == target.identity else { return false }
        return te_set_background(target.identity.pid, target.identity.startSeconds,
                                 target.identity.startMicroseconds, enabled ? 1 : 0) == 0
    }
    @discardableResult static func signal(_ target: ControlTarget, number: Int32) -> Bool {
        guard number == SIGCONT ? identity(target.identity.pid) == target.identity : matches(target) else { return false }
        return te_signal_process(target.identity.pid, target.identity.startSeconds,
                                 target.identity.startMicroseconds, number) == 0
    }
    static func isAlive(_ identity: ProcessIdentity) -> Bool {
        guard let current = sample(identity.pid) else { return false }
        return current.identity == identity && current.status != 5
    }
}

enum Recovery {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "TaskEase", isDirectory: true)
    }
    static func url(testing: Bool = false) -> URL {
        directory.appendingPathComponent(testing ? "test-recovery.json" : "recovery.json")
    }
    static func read(testing: Bool = false) -> RecoveryRecord? {
        guard let data = try? Data(contentsOf: url(testing: testing)) else { return nil }
        return try? JSONDecoder().decode(RecoveryRecord.self, from: data)
    }
    static func save(_ record: RecoveryRecord, testing: Bool = false) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(record)
        try data.write(to: url(testing: testing), options: .atomic)
    }
    @discardableResult static func restore(testing: Bool = false, force: Bool = false) -> Int {
        guard let record = read(testing: testing), record.worker.uid == geteuid() else { return 0 }
        guard force || !NativeProcess.isAlive(record.worker) else { return 0 }
        var restored = 0
        for target in record.suspension where NativeProcess.identity(target.identity.pid) == target.identity {
            if NativeProcess.signal(target, number: SIGCONT) { restored += 1 }
        }
        for target in record.background where NativeProcess.identity(target.identity.pid) == target.identity {
            if NativeProcess.background(target, enabled: false) { restored += 1 }
        }
        try? FileManager.default.removeItem(at: url(testing: testing))
        return restored
    }
}

@MainActor
final class ProcessMonitor {
    private var previous: [ProcessIdentity: ProcessSample] = [:]
    private var previousWall: UInt64?
    private var previousCPU: TECPUTicks?
    private var lastGPUTime: UInt64 = 0
    private var cachedGPU: Double?

    func sample() -> ([AppReading], SystemReading) {
        let now = NativeProcess.now
        let elapsed = previousWall.map { Double(now &- $0) }
        let ownID = Bundle.main.bundleIdentifier
        let running = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.bundleIdentifier != nil && $0.bundleURL != nil &&
            $0.bundleIdentifier != ownID && $0.activationPolicy != .prohibited &&
            !($0.bundleURL?.path.contains(".app/Contents/") ?? false)
        }
        let grouped = Dictionary(grouping: running, by: { $0.bundleIdentifier ?? "" })
        var apps: [String: AppReading] = [:]
        for (id, instances) in grouped {
            guard let first = instances.first else { continue }
            let roots = Array(Set(instances.compactMap { $0.bundleURL?.resolvingSymlinksInPath().path }))
            apps[id] = AppReading(id: id, name: first.localizedName ?? id, bundlePaths: roots,
                                  primaryPIDs: Set(instances.map { $0.processIdentifier }), targets: [], samples: [],
                                  cpuPercent: elapsed == nil ? nil : 0, memoryBytes: 0, readRate: 0, writeRate: 0,
                                  canControl: !id.hasPrefix("com.apple.") && !roots.contains { $0.hasPrefix("/System/") },
                                  isHidden: instances.allSatisfy { $0.isHidden })
        }
        var next: [ProcessIdentity: ProcessSample] = [:]
        for pid in NativeProcess.pids() {
            guard let identity = NativeProcess.identity(pid), identity.uid == geteuid(),
                  let executable = NativeProcess.path(pid),
                  let id = apps.first(where: { item in
                      item.value.primaryPIDs.contains(pid) || item.value.bundlePaths.contains { executable.hasPrefix($0 + "/Contents/") }
                  })?.key,
                  let reading = NativeProcess.sample(pid), reading.identity == identity else { continue }
            next[identity] = reading
            apps[id]?.samples.append(reading)
            apps[id]?.memoryBytes += reading.memoryBytes
            if let root = apps[id]?.bundlePaths.first(where: { executable.hasPrefix($0 + "/Contents/") }) {
                apps[id]?.targets.append(ControlTarget(identity: identity, executablePath: executable, bundlePath: root))
            }
            if let elapsed, elapsed > 0, let old = previous[identity] {
                apps[id]?.cpuPercent? += 100 * Double(reading.cpuTicks >= old.cpuTicks ? reading.cpuTicks - old.cpuTicks : 0) / elapsed
                let seconds = elapsed / NativeProcess.ticksPerSecond
                apps[id]?.readRate += Double(reading.readBytes >= old.readBytes ? reading.readBytes - old.readBytes : 0) / seconds
                apps[id]?.writeRate += Double(reading.writeBytes >= old.writeBytes ? reading.writeBytes - old.writeBytes : 0) / seconds
            }
        }
        for id in Array(apps.keys) where apps[id]?.samples.isEmpty == true {
            apps[id]?.cpuPercent = nil
            apps[id]?.canControl = false
        }
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
        previous = next; previousWall = now
        return (apps.values.sorted { ($0.cpuPercent ?? 0) > ($1.cpuPercent ?? 0) }, system)
    }
}
