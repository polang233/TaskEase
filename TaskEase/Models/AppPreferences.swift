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

struct AppPreferences: Codable, Equatable, Sendable {
    var showSystemApps = false
    var refreshInterval: DisplayRefreshInterval = .two
    var theme: ThemeMode = .system
}
