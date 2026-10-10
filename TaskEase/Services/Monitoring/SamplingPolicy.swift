import Foundation

enum SamplingPolicy {
    /// Display refresh and the worker's lease are independent. A slow UI refresh
    /// must never interrupt active controls or postpone a background deadline.
    static func nextInterval(displayVisible: Bool, displayInterval: TimeInterval,
                             controlMonitoring: Bool, waitingSeconds: [TimeInterval]) -> TimeInterval? {
        var interval: TimeInterval? = displayVisible ? displayInterval : nil
        if controlMonitoring { interval = min(interval ?? 2, 2) }
        for remaining in waitingSeconds where remaining > 0 {
            interval = min(interval ?? remaining, max(0.05, remaining))
        }
        return interval
    }
}
