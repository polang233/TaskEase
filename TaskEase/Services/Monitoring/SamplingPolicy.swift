import Foundation

/// 按可见性、控制心跳和后台等待期限决定下一次刷新时间。
enum SamplingPolicy {
    /// 显示刷新与控制心跳分开计时，取最早期限保持等待与恢复及时。
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
