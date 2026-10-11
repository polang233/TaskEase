import Foundation

enum DisplayRefreshInterval: Int, Codable, CaseIterable, Sendable {
    case one = 1, two = 2, five = 5, ten = 10

    var seconds: TimeInterval { TimeInterval(rawValue) }
    var title: String { "\(rawValue) 秒" }
}

enum ThemeMode: String, Codable, CaseIterable, Sendable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}

/// 保存系统应用筛选、刷新间隔与外观偏好。
struct AppPreferences: Codable, Equatable, Sendable {
    var showSystemApps = false
    var refreshInterval: DisplayRefreshInterval = .two
    var theme: ThemeMode = .system
    var refreshOnlyInForeground = true
    var networkFeaturesEnabled = false
    var showNetworkActivity = true
    var networkActivityVisible: Bool { networkFeaturesEnabled && showNetworkActivity }
}

// 新增偏好使用默认值，读取已有配置时保留原有外观和刷新间隔。
extension AppPreferences {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        networkFeaturesEnabled = try values.decodeIfPresent(Bool.self, forKey: .networkFeaturesEnabled) ?? false
        showNetworkActivity = try values.decodeIfPresent(Bool.self, forKey: .showNetworkActivity) ?? true
        showSystemApps = try values.decodeIfPresent(Bool.self, forKey: .showSystemApps) ?? false
        refreshInterval = try values.decodeIfPresent(DisplayRefreshInterval.self, forKey: .refreshInterval) ?? .two
        theme = try values.decodeIfPresent(ThemeMode.self, forKey: .theme) ?? .system
        refreshOnlyInForeground = try values.decodeIfPresent(Bool.self, forKey: .refreshOnlyInForeground) ?? true
    }
}
