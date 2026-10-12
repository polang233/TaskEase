import Foundation

/// 统一格式化资源指标，无法读取的数据以占位符展示。
@MainActor
enum Display {
    private static let memoryFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    static func percent(_ value: Double?) -> String {
        value.map { String(format: "%.1f%%", $0) } ?? "—"
    }

    static func bytes(_ value: UInt64) -> String {
        memoryFormatter.string(fromByteCount: Int64(min(value, UInt64(Int64.max))))
    }

    static func memory(_ app: AppReading) -> String {
        !app.isRunning || (app.samples.isEmpty && app.memoryBytes == 0) ? "—" : bytes(app.memoryBytes)
    }

    static func rate(_ value: Double) -> String { bytes(UInt64(max(0, value))) + "/s" }
    static func networkRate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        return bytes(UInt64(min(value, Double(Int64.max)))) + "/s"
    }
    static func wakeups(_ value: Double) -> String { String(format: "%.1f/s", value) }

    /// 概览使用紧凑的 GB 数字，压缩值与物理内存保持相同口径。
    static func gigabytes(_ value: UInt64?) -> String {
        value.map { String(format: "%.1f", Double($0) / 1_073_741_824) } ?? "—"
    }

    /// 全局网速固定使用十进制 MB/s，避免单位切换令一行内容不断变宽。
    static func megabytesPerSecond(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        let megabytes = value / 1_000_000
        return String(format: megabytes < 100 ? "%.2f" : "%.1f", megabytes)
    }

    /// 概览网速：1 MB/s 以下用 KB/s，减少小数位；1 MB 为 1,000,000 字节。
    static func compactRate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        if value < 1_000_000 { return String(format: "%.0f KB/s", value / 1000) }
        let megabytes = value / 1_000_000
        return String(format: megabytes < 100 ? "%.1f MB/s" : "%.0f MB/s", megabytes)
    }

    static func temperature(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f°C", value)
    }
}
