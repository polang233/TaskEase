import Foundation

/// 建议的限制方式，套用时生成对应规则。
enum SuggestedMethod: String, Codable, CaseIterable, Sendable {
    case pause, lowerPriority, limitCPU

    var title: String {
        switch self {
        case .pause: String(localized: "suggestion.method.pause")
        case .lowerPriority: String(localized: "suggestion.method.priority")
        case .limitCPU: String(localized: "suggestion.method.cpu")
        }
    }

    /// 生效时机使用默认的离开前台 3 秒。
    var rule: AppRule {
        switch self {
        case .pause: AppRule(isEnabled: true, limitsPerformance: true, performance: .suspend)
        case .lowerPriority: AppRule(isEnabled: true, limitsPerformance: false, lowersPriority: true)
        case .limitCPU: AppRule(isEnabled: true, limitsPerformance: true, performance: .budget, cpuPercent: 20)
        }
    }
}

/// 按应用用途粗分的类型，决定推荐方式。
enum SuggestedKind: String, Sendable {
    /// 持续显示画面（视频解码并在屏幕上合成，或自身 GPU 占用高）：暂停最省。
    case visual
    /// 需要及时收消息的聊天、邮件类：暂停会收不到通知，改为降低优先级。
    case notifying
    /// 后台播放声音的音乐、播客类：暂停会中断播放，改为降低优先级。
    case media
    /// 其他：限制 CPU 到 20%。
    case general

    var method: SuggestedMethod {
        switch self {
        case .visual: .pause
        case .notifying, .media: .lowerPriority
        case .general: .limitCPU
        }
    }

    var reason: String {
        switch self {
        case .visual: String(localized: "suggestion.reason.visual")
        case .notifying: String(localized: "suggestion.reason.notifying")
        case .media: String(localized: "suggestion.reason.media")
        case .general: String(localized: "suggestion.reason.general")
        }
    }
}

/// 一条建议：应用在后台未受限时的平均占用超过阈值。
struct Suggestion: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let cpuPercent: Double
    let gpuPercent: Double?
    let compositingPercent: Double
    let kind: SuggestedKind
    var method: SuggestedMethod { kind.method }
}

/// 建议阈值与忽略记录，保存在 suggestions.v1。
struct SuggestionSettings: Codable, Equatable, Sendable {
    /// 后台平均 CPU 阈值，单核口径。
    var cpuThreshold: Double = 10
    /// 后台平均 GPU 阈值（含画面合成）。
    var gpuThreshold: Double = 5
    var dismissed: Set<String> = []
    /// 用户关掉提示条时的建议；出现新的建议才再次显示提示条。
    var bannerHiddenFor: Set<String> = []

    static let cpuChoices: [Double] = [5, 10, 20, 40]
    static let gpuChoices: [Double] = [3, 5, 10, 20]

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        cpuThreshold = try values.decodeIfPresent(Double.self, forKey: .cpuThreshold) ?? 10
        gpuThreshold = try values.decodeIfPresent(Double.self, forKey: .gpuThreshold) ?? 5
        dismissed = try values.decodeIfPresent(Set<String>.self, forKey: .dismissed) ?? []
        bannerHiddenFor = try values.decodeIfPresent(Set<String>.self, forKey: .bannerHiddenFor) ?? []
    }

    func validated() -> SuggestionSettings {
        var settings = self
        settings.cpuThreshold = cpuThreshold.isFinite ? min(200, max(1, cpuThreshold)) : 10
        settings.gpuThreshold = gpuThreshold.isFinite ? min(100, max(1, gpuThreshold)) : 5
        return settings
    }
}

/// 根据后台基线列出建议。纯函数，界面与测试共用。
enum SuggestionEngine {
    /// 需要至少观察一分钟后台占用，避免刚切走时的短暂峰值触发建议。
    static let minimumSeconds: TimeInterval = 60
    /// 平均画面合成超过这个比例视为持续显示画面。
    static let compositingFloor = 1.0

    struct Candidate: Sendable {
        let id: String
        let name: String
        /// 应用包 Info.plist 中的 LSApplicationCategoryType。
        let category: String?
    }

    /// `candidates` 为可以设置规则的运行中应用；已有规则、已忽略的应用由调用方排除或在此按设置排除。
    static func suggestions(baselines: [String: UsageBaseline], candidates: [Candidate], excluded: Set<String>,
                            settings: SuggestionSettings, now: Date) -> [Suggestion] {
        let settings = settings.validated()
        return candidates.compactMap { candidate -> Suggestion? in
            guard !excluded.contains(candidate.id), !settings.dismissed.contains(candidate.id),
                  let baseline = baselines[candidate.id], baseline.isFresh(at: now) else { return nil }
            let cpu = baseline.cpuSeconds >= minimumSeconds ? baseline.cpuPercent : nil
            let gpu = baseline.gpuSeconds >= minimumSeconds ? baseline.gpuPercent : nil
            let busy = (cpu ?? 0) >= settings.cpuThreshold || (gpu ?? 0) >= settings.gpuThreshold
            guard busy else { return nil }
            let compositing = gpu == nil ? 0 : baseline.compositingPercent
            return Suggestion(id: candidate.id, name: candidate.name, cpuPercent: cpu ?? baseline.cpuPercent, gpuPercent: gpu,
                              compositingPercent: compositing,
                              kind: kind(id: candidate.id, name: candidate.name, category: candidate.category,
                                         gpuPercent: gpu, compositingPercent: compositing, settings: settings))
        }.sorted {
            let left = $0.cpuPercent + ($0.gpuPercent ?? 0), right = $1.cpuPercent + ($1.gpuPercent ?? 0)
            if left != right { return left > right }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// 先看是否需要后台通知或播放，再看是否持续显示画面；类别来自应用包声明，名称关键词作补充。
    static func kind(id: String, name: String, category: String?, gpuPercent: Double?, compositingPercent: Double,
                     settings: SuggestionSettings) -> SuggestedKind {
        let text = (id + " " + name).lowercased()
        let category = category?.lowercased() ?? ""
        if category == "public.app-category.music" || mediaKeywords.contains(where: { text.contains($0) }) { return .media }
        if category == "public.app-category.social-networking" || notifyingKeywords.contains(where: { text.contains($0) }) {
            return .notifying
        }
        if compositingPercent >= compositingFloor || (gpuPercent ?? 0) >= settings.gpuThreshold { return .visual }
        return .general
    }

    private static let notifyingKeywords = [
        "slack", "teams", "wechat", "weixin", "wecom", "wework", "telegram", "whatsapp", "discord", "lark", "feishu",
        "dingtalk", "tencent.qq", "signal", "messenger", "skype", "naver.line", "zoom", "outlook", "mail", "spark",
        "thunderbird", "微信", "钉钉", "飞书", "企业微信", "邮件"
    ]
    private static let mediaKeywords = [
        "spotify", "music", "podcast", "audible", "neteasemusic", "qqmusic", "kugou", "kuwo", "网易云音乐", "音乐"
    ]
}
