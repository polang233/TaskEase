import Foundation

/// 按可见性、控制心跳和后台等待期限决定下一次刷新时间。
enum SamplingPolicy {
    /// 菜单栏面板打开时提供实时数据。管理窗口默认只在可见且位于前台时刷新；
    /// 用户关闭“仅在前台刷新”后，只要窗口开着（被遮挡或最小化也算）就持续采样，后台数据保持连贯。
    static func shouldRefreshDisplay(managementOpen: Bool, managementVisible: Bool, menuVisible: Bool,
                                     isForeground: Bool, onlyInForeground: Bool) -> Bool {
        menuVisible || (onlyInForeground ? managementVisible && isForeground : managementOpen)
    }

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
