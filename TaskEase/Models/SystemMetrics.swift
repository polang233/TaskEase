import Foundation

/// 压缩内存是已用内存的一部分，不能再次相加。
struct SystemMemoryReading: Equatable, Sendable {
    let usedBytes: UInt64
    let totalBytes: UInt64
    let compressedBytes: UInt64
    var swapBytes: UInt64? = nil
    var percent: Double? { totalBytes > 0 ? 100 * Double(usedBytes) / Double(totalBytes) : nil }
}

/// 全局传输速度的单位为字节/秒；缺少差分基线时为 nil。
struct SystemNetworkReading: Equatable, Sendable {
    let receiveRate: Double?
    let sendRate: Double?
}

struct InterfaceByteCount: Equatable, Sendable {
    let index: UInt32
    let received: UInt64
    let sent: UInt64
}

/// 网卡各自保留基线，断线、重连、计数重置与长时间暂停都重新起算。
struct SystemNetworkSampler {
    private var previous: [UInt32: InterfaceByteCount] = [:]
    private var previousTime: UInt64?

    mutating func reset() { previous.removeAll(); previousTime = nil }

    mutating func sample(_ counters: [InterfaceByteCount], now: UInt64) -> SystemNetworkReading {
        let current = Dictionary(counters.map { ($0.index, $0) }, uniquingKeysWith: { _, next in next })
        defer { previous = current; previousTime = now }
        if counters.isEmpty { return .init(receiveRate: 0, sendRate: 0) }
        guard let previousTime, now > previousTime else { return .init(receiveRate: nil, sendRate: nil) }
        let elapsed = Double(now - previousTime) / NativeProcess.ticksPerSecond
        guard elapsed <= 20 else { return .init(receiveRate: nil, sendRate: nil) }
        var received = 0.0, sent = 0.0, comparable = false
        for (index, counter) in current {
            guard let old = previous[index], counter.received >= old.received, counter.sent >= old.sent else { continue }
            comparable = true
            received += Double(counter.received - old.received) / elapsed
            sent += Double(counter.sent - old.sent) / elapsed
        }
        return .init(receiveRate: comparable ? received : nil, sendRate: comparable ? sent : nil)
    }
}

/// 配色仅帮助扫读占用，不替代系统内存压力或热状态。
enum MetricSeverity: Int, Equatable, Sendable {
    case unknown, normal, elevated, high, critical

    static func utilization(_ value: Double?) -> Self {
        guard let value, value.isFinite, value >= 0 else { return .unknown }
        switch value {
        case ..<40: return .normal
        case ..<60: return .elevated
        case ..<80: return .high
        default: return .critical
        }
    }

    static func temperature(_ value: Double?) -> Self {
        guard let value, value.isFinite else { return .unknown }
        switch value {
        case ..<50: return .normal
        case ..<70: return .elevated
        case ..<85: return .high
        default: return .critical
        }
    }

    /// 应用 CPU 数字采用单核口径，颜色按全部核心能力归一，避免把一个核心误当成整机满载。
    static func applicationCPU(_ value: Double?, coreCount: Int = ProcessInfo.processInfo.activeProcessorCount) -> Self {
        utilization(value.map { $0 / Double(max(1, coreCount)) })
    }
}

/// 系统热状态。逻辑只依赖枚举值，显示名称在界面层本地化。
enum ThermalLevel: String, Equatable, Sendable, CaseIterable {
    case nominal, fair, serious, critical, unknown

    var title: String {
        switch self {
        case .nominal: String(localized: "thermal.nominal")
        case .fair: String(localized: "thermal.fair")
        case .serious: String(localized: "thermal.serious")
        case .critical: String(localized: "thermal.critical")
        case .unknown: String(localized: "thermal.unknown")
        }
    }

    /// 用于配色的严重程度，0...1；未知时为 nil。
    var severity: Double? {
        switch self {
        case .nominal: 0
        case .fair: 0.45
        case .serious: 0.75
        case .critical: 1
        case .unknown: nil
        }
    }
}
