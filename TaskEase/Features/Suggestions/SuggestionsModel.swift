import Foundation
import Observation

/// 保存建议阈值与忽略记录，并缓存应用包声明的类别。
@MainActor @Observable
final class SuggestionsModel {
    private(set) var settings: SuggestionSettings
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var categories: [String: String?] = [:]
    static let key = "suggestions.v1"

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        settings = defaults?.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(SuggestionSettings.self, from: $0) }?.validated() ?? SuggestionSettings()
    }

    func update(_ change: (inout SuggestionSettings) -> Void) {
        var next = settings
        change(&next)
        next = next.validated()
        guard next != settings else { return }
        settings = next
        if let defaults, let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: Self.key) }
    }

    func dismiss(_ id: String) { update { $0.dismissed.insert(id) } }
    func restoreDismissed() { update { $0.dismissed.removeAll() } }
    func hideBanner(for ids: Set<String>) { update { $0.bannerHiddenFor = ids } }

    /// 读取应用包 Info.plist 的 LSApplicationCategoryType，按应用缓存。
    func category(for app: AppReading) -> String? {
        if let cached = categories[app.id] { return cached }
        let value = app.bundlePaths.first.flatMap { Bundle(path: $0)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String }
        categories[app.id] = value
        return value
    }
}
