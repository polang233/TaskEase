import Foundation

/// URL Scheme 与快捷指令共用的自动化命令。
///
/// - `taskease://enable`、`taskease://disable`、`taskease://toggle`：开关“启用限制”。
/// - `taskease://pause?app=<bundle id>&minutes=60`：在后台时临时暂停应用，1 至 240 分钟，默认 60。
/// - `taskease://resume?app=<bundle id>`：立即恢复。
enum AutomationCommand: Equatable, Sendable {
    /// nil 表示切换。
    case setLimits(Bool?)
    case pause(app: String, minutes: Double)
    case resume(app: String)

    static let scheme = "taskease"
    /// 设置“允许链接控制”，默认关闭；快捷指令不受影响。
    static let urlEnabledKey = "automationURLEnabled"

    static func parse(_ url: URL) -> AutomationCommand? {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        // 同时接受 taskease://pause 与 taskease:pause 两种写法。
        let action = (components.host ?? components.path).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let query = Dictionary((components.queryItems ?? []).compactMap { item in item.value.map { (item.name.lowercased(), $0) } },
                               uniquingKeysWith: { first, _ in first })
        let app = query["app"]?.trimmingCharacters(in: .whitespaces) ?? ""
        switch action {
        case "enable": return .setLimits(true)
        case "disable": return .setLimits(false)
        case "toggle": return .setLimits(nil)
        case "pause":
            guard !app.isEmpty else { return nil }
            let minutes = query["minutes"].flatMap(Double.init) ?? TemporaryAction.defaultMinutes
            return .pause(app: app, minutes: TemporaryAction.clampedMinutes(minutes))
        case "resume":
            return app.isEmpty ? nil : .resume(app: app)
        default:
            return nil
        }
    }
}

/// 自动化命令的执行结果；消息用于快捷指令的对话框。
struct AutomationOutcome: Equatable, Sendable {
    let succeeded: Bool
    let message: String
}
