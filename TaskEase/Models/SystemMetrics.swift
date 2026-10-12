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
