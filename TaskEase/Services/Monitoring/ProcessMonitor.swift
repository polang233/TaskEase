import AppKit
import Foundation
import CoreGraphics
import Darwin

/// 在主 actor 上复制 AppKit 应用信息，再传递给采样 actor。
struct RunningApplication: Sendable {
    let id: String
    let name: String
    /// 搜索用的其他名称（英文包名、文件名等），不参与显示。
    var aliases: [String] = []
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
            let name = first.localizedName ?? id
            let app = RunningApplication(id: id, name: name,
                                         aliases: first.bundleURL.map { AppSearch.aliases(for: $0, excluding: name) } ?? [],
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
                networkStatus: .unavailable(String(localized: "network.monitor.unavailable")))
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
    private var previousGPU: [ProcessIdentity: UInt64] = [:]
    /// 全部 GPU 客户端按 PID 的上次累计时间，用于列出占用来源（含其他用户的进程）。
    private var previousGPUByPID: [Int32: (name: String, time: UInt64)] = [:]
    private var previousWall: UInt64?
    private var previousCPU: TECPUTicks?
    private var paths: [ProcessIdentity: String] = [:]
    private var pathCacheTime: UInt64 = 0
    private var lastHardwareTime: UInt64 = 0
    private var cachedGPU: Double?
    private var cachedTemperature: Double?
    private var systemNetwork = SystemNetworkSampler()

    mutating func reset() {
        previous.removeAll()
        previousGPU.removeAll()
        previousGPUByPID.removeAll()
        previousWall = nil
        previousCPU = nil
        systemNetwork.reset()
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
                                     isHidden: app.isHidden, aliases: app.aliases)
            for pid in app.primaryPIDs { primaryOwners[pid] = app.id }
        }
        // GPU 客户端时间只在显示采样读取；控制采样不访问 IORegistry。
        let gpuTimes = includeSystem ? Self.gpuTimes() : [:]
        var nextGPU: [ProcessIdentity: UInt64] = [:]
        var gpuComparable: Set<String> = []
        var gpuAppPIDs: Set<Int32> = []
        var pidOwners: [Int32: String] = [:]
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
            pidOwners[pid] = id
            apps[id]?.samples.append(reading)
            apps[id]?.memoryBytes += reading.memoryBytes
            if let root = apps[id]?.bundlePaths.first(where: { executable.hasPrefix($0 + "/Contents/") }) {
                apps[id]?.targets.append(ControlTarget(identity: identity, executablePath: executable, bundlePath: root))
            }
            if let gpu = gpuTimes[pid]?.time {
                gpuAppPIDs.insert(pid)
                nextGPU[identity] = gpu
                if let elapsed, elapsed > 0, let old = previousGPU[identity], gpu >= old {
                    let seconds = elapsed / NativeProcess.ticksPerSecond
                    let current = apps[id]?.gpuPercent ?? 0
                    apps[id]?.gpuPercent = current + Double(gpu - old) / 1e9 / seconds * 100
                    gpuComparable.insert(id)
                }
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
            if includeSystem, previousWall != nil, !gpuComparable.contains(id) { apps[id]?.gpuPercent = 0 }
            if let gpu = apps[id]?.gpuPercent { apps[id]?.gpuPercent = min(100, gpu) }
            if apps[id]?.samples.isEmpty == true { apps[id]?.canControl = false }
        }
        var system = includeSystem ? sampleSystem(now: now) : nil
        if includeSystem, let elapsed, elapsed > 0 {
            system?.gpuSources = Self.gpuSources(apps: &apps, owners: pidOwners, times: gpuTimes, previous: previousGPUByPID,
                                                 excluding: gpuAppPIDs, seconds: elapsed / NativeProcess.ticksPerSecond)
        }
        previous = next
        previousGPU = nextGPU
        previousGPUByPID = gpuTimes
        previousWall = now
        paths = nextPaths
        let sorted = apps.values.sorted {
            if $0.cpuPercent == $1.cpuPercent { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return ($0.cpuPercent ?? -1) > ($1.cpuPercent ?? -1)
        }
        return MonitoringSnapshot(apps: sorted, system: system)
    }

    /// 同一进程可能持有多个 GPU 客户端，按 PID 合并累计时间。
    private static func gpuTimes() -> [Int32: (name: String, time: UInt64)] {
        var buffer = [TEProcessGPU](repeating: TEProcessGPU(), count: 512)
        let count = te_gpu_process_times(&buffer, Int32(buffer.count))
        guard count > 0 else { return [:] }
        var result: [Int32: (name: String, time: UInt64)] = [:]
        for var item in buffer.prefix(Int(count)) {
            let name = withUnsafeBytes(of: &item.name) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
            result[item.pid] = (name, (result[item.pid]?.time ?? 0) &+ item.gpuNanoseconds)
        }
        return result
    }

    /// 已识别应用按应用合并；不属于任何应用的进程（WindowServer 等系统进程）按进程名合并。只保留前五个且不低于 0.5%。
    /// 正在显示视频画面的应用会让 WindowServer 持续合成，这部分按估算移到应用名下，见 `compositingShares`。
    private static func gpuSources(apps: inout [String: AppReading], owners: [Int32: String],
                                   times: [Int32: (name: String, time: UInt64)],
                                   previous: [Int32: (name: String, time: UInt64)], excluding appPIDs: Set<Int32>,
                                   seconds: Double) -> [GPUSource] {
        var processes: [String: Double] = [:]
        for (pid, current) in times where !appPIDs.contains(pid) {
            guard let old = previous[pid], old.name == current.name, current.time >= old.time, !current.name.isEmpty else { continue }
            processes[current.name, default: 0] += Double(current.time - old.time) / 1e9 / seconds * 100
        }
        let windowServer = processes[windowServerName] ?? 0
        let shares = compositingShares(windowServer: windowServer, owners: owners)
        for (id, share) in shares { apps[id]?.compositingGPUPercent = share }
        if !shares.isEmpty { processes[windowServerName] = max(0, windowServer - shares.values.reduce(0, +)) }

        var sources = processes.map { GPUSource(name: $0.key, percent: min(100, $0.value)) }
        for app in apps.values {
            guard let total = app.totalGPUPercent, total > 0 else { continue }
            sources.append(GPUSource(name: app.name, percent: total, compositing: app.compositingGPUPercent ?? 0))
        }
        return Array(sources.filter { $0.percent >= 0.5 }.sorted { $0.percent > $1.percent }.prefix(5))
    }

    private static let windowServerName = "WindowServer"
    /// 没有视频画面时 WindowServer 自身的合成开销，不归到任何应用。
    private static let compositingFloor = 5.0

    /// 系统不提供按窗口拆分的合成开销。实测正在显示视频画面（使用硬件解码器）的应用窗口在屏幕上时，
    /// WindowServer 的 GPU 明显升高，隐藏窗口后回落，因此把超出底线的部分按这些应用的可见窗口面积分摊。
    /// 没有应用在解码时不读取窗口列表。
    private static func compositingShares(windowServer: Double, owners: [Int32: String]) -> [String: Double] {
        guard windowServer > compositingFloor else { return [:] }
        var buffer = [Int32](repeating: 0, count: 32)
        let count = te_video_decoder_owners(&buffer, Int32(buffer.count))
        let decoding = Set(buffer.prefix(max(0, Int(count))).compactMap { owners[$0] })
        guard !decoding.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [:] }
        var areas: [String: Double] = [:]
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? Int32, let id = owners[pid], decoding.contains(id),
                  let bounds = window[kCGWindowBounds as String] as? [String: Double] else { continue }
            areas[id, default: 0] += (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
        }
        let total = areas.values.reduce(0, +)
        guard total > 0 else { return [:] }
        let attributable = windowServer - compositingFloor
        return areas.mapValues { attributable * $0 / total }
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
        // 驱动与传感器只为可见数据面板读取，并共用四秒缓存。
        if lastHardwareTime == 0 || Double(now &- lastHardwareTime) / NativeProcess.ticksPerSecond >= 4 {
            let raw = te_gpu_percent()
            cachedGPU = raw >= 0 ? raw : nil
            let temperature = te_chip_temperature()
            cachedTemperature = temperature >= 0 ? temperature : nil
            lastHardwareTime = now
        }
        system.gpuPercent = cachedGPU
        system.temperatureCelsius = cachedTemperature
        var memory = TESystemMemory()
        if te_system_memory(&memory) != 0 {
            system.memory = SystemMemoryReading(usedBytes: memory.usedBytes, totalBytes: memory.totalBytes,
                                               compressedBytes: memory.compressedBytes,
                                               swapBytes: memory.swapAvailable != 0 ? memory.swapUsedBytes : nil)
        }
        var interfaces = [TESystemNetwork](repeating: TESystemNetwork(), count: 64)
        let count = te_system_network(&interfaces, Int32(interfaces.count))
        if count >= 0 {
            let counters = interfaces.prefix(Int(count)).map {
                InterfaceByteCount(index: $0.interfaceIndex, received: $0.receivedBytes, sent: $0.sentBytes)
            }
            system.network = systemNetwork.sample(counters, now: now)
        } else { systemNetwork.reset() }
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: system.thermal = .nominal
        case .fair: system.thermal = .fair
        case .serious: system.thermal = .serious
        case .critical: system.thermal = .critical
        @unknown default: system.thermal = .unknown
        }
        return system
    }
}
