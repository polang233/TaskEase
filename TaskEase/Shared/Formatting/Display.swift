import Foundation

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
    static func wakeups(_ value: Double) -> String { String(format: "%.1f/s", value) }
}
