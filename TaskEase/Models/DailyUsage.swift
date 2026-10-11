import Foundation

/// 只记录 TaskEase 的配置概况，不包含被管理应用的身份或规则明细。
struct UsageContext: Codable, Equatable, Sendable {
    var cpuRuleCount = 0
    var networkRuleCount = 0
    var managementEnabled = false
    var theme = "system"
    var refreshSeconds = 2
    var networkDisplayEnabled = true
    var foregroundRefreshOnly = true
}

/// 活跃事件携带随机安装标识、环境和本应用的功能使用概况。
struct DailyUsageEvent: Codable, Equatable, Sendable {
    let id: UUID
    let installationID: UUID
    let timestamp: Date
    let localDay: String
    let appVersion: String
    let appBuild: String
    let osVersion: String
    let region: String
    let isTest: Bool
    var language: String? = nil
    var timeZone: String? = nil
    var usage: UsageContext? = nil

    static func capture(installationID: UUID, now: Date, calendar: Calendar, isTest: Bool = false,
                        usage: UsageContext? = nil) -> DailyUsageEvent {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return DailyUsageEvent(id: UUID(), installationID: installationID, timestamp: now,
            localDay: DailyUsageSchedule.day(now, calendar: calendar),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            region: Locale.current.region?.identifier ?? "unknown", isTest: isTest,
            language: Locale.preferredLanguages.first ?? "unknown", timeZone: calendar.timeZone.identifier, usage: usage)
    }
}

/// 保留一个待发送事件，重试复用 UUID 与时间戳，供 PostHog 去重。
struct DailyUsageState: Codable, Equatable, Sendable {
    var installationID: UUID?
    var lastSuccess: Date?
    var pending: DailyUsageEvent?
    var attempts = 0
    var retryAfter: Date?
}

/// 当天首次活动即上报；持续运行每六小时发送，失败有间隔和窗口上限。
enum DailyUsageSchedule {
    enum Action: Equatable { case send, wait(Date) }
    static let interval: TimeInterval = 6 * 3600
    static let retryInterval: TimeInterval = 5 * 60

    static func calendar(timeZone: TimeZone = .autoupdatingCurrent) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        return value
    }

    static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func action(now: Date, state: DailyUsageState, calendar: Calendar) -> Action {
        let start = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        // 跨日及时统计；同日重启、唤醒和网络通知共享六小时去重期限。
        if let success = state.lastSuccess, success >= start, now < success.addingTimeInterval(interval) {
            return .wait(min(success.addingTimeInterval(interval), tomorrow))
        }
        if let pending = state.pending, pending.localDay == day(now, calendar: calendar) {
            if state.attempts >= 3, now < pending.timestamp.addingTimeInterval(interval) {
                return .wait(min(pending.timestamp.addingTimeInterval(interval), tomorrow))
            }
            if state.attempts < 3, let retry = state.retryAfter, now < retry { return .wait(min(retry, tomorrow)) }
        }
        return .send
    }
}
