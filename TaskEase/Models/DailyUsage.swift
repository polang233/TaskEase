import Foundation

/// 每日活跃事件只包含安装随机标识和允许公开说明的基础环境字段。
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

    static func capture(installationID: UUID, now: Date, calendar: Calendar, isTest: Bool = false) -> DailyUsageEvent {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return DailyUsageEvent(id: UUID(), installationID: installationID, timestamp: now,
            localDay: DailyUsageSchedule.day(now, calendar: calendar),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            region: Locale.current.region?.identifier ?? "unknown", isTest: isTest)
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

/// 当地中午上报；有过成功或达到重试上限后等到下一天，不补发历史天数。
enum DailyUsageSchedule {
    enum Action: Equatable { case send, wait(Date) }

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
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? start.addingTimeInterval(43200)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: noon) ?? noon.addingTimeInterval(86400)
        // 时钟回退时已有成功日期也阻止重复上报。
        if let success = state.lastSuccess, success >= start { return .wait(tomorrow) }
        if now < noon { return .wait(noon) }
        if state.pending?.localDay == day(now, calendar: calendar) {
            if state.attempts >= 3 { return .wait(tomorrow) }
            if let retry = state.retryAfter, now < retry { return .wait(min(retry, tomorrow)) }
        }
        return .send
    }
}
