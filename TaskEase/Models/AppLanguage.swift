import Foundation

/// 界面语言。选择写入本应用偏好域的 AppleLanguages，重新启动后由系统按此加载本地化资源；
/// 跟随系统时移除该项。语言名称用各自的语言显示，方便在看不懂当前界面时也能找到。
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system = ""
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "settings.language.system")
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        }
    }

    /// 本应用偏好域里保存的选择；不读取全局域，避免把系统语言误当成用户选择。
    static var saved: AppLanguage {
        guard let id = Bundle.main.bundleIdentifier,
              let languages = UserDefaults.standard.persistentDomain(forName: id)?["AppleLanguages"] as? [String],
              let first = languages.first else { return .system }
        return allCases.first { $0 != .system && first.hasPrefix($0.rawValue) } ?? .system
    }

    /// 本次启动时生效的选择，用于判断是否需要重新启动。
    static let launched = saved

    func save(to defaults: UserDefaults = .standard) {
        if self == .system { defaults.removeObject(forKey: "AppleLanguages") }
        else { defaults.set([rawValue], forKey: "AppleLanguages") }
    }
}
