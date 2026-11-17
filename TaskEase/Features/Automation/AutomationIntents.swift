import AppIntents
import AppKit
import Foundation

/// 快捷指令在本应用进程内运行，通过这里找到正在使用的模型。
@MainActor
enum AutomationCenter {
    static weak var model: AppModel?

    /// 系统为执行快捷指令刚启动本应用时，模型可能稍后才创建，最多等两秒。
    static func current() async throws -> AppModel {
        for _ in 0..<20 {
            if let model { return model }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw AutomationError.unavailable
    }
}

enum AutomationError: Error, CustomLocalizedStringResourceConvertible {
    case unavailable
    case failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unavailable: "automation.error.unavailable"
        case .failed(let message): "\(message)"
        }
    }
}

/// 快捷指令中选择的应用：当前用户正在运行、可以设置规则的应用。
struct ApplicationEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "intent.app.type"
    static let defaultQuery = ApplicationQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(id)")
    }
}

struct ApplicationQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ApplicationEntity] {
        let running = await Self.running()
        return identifiers.map { id in
            running.first { $0.id == id } ?? ApplicationEntity(id: id, name: id)
        }
    }

    func entities(matching string: String) async throws -> [ApplicationEntity] {
        let running = await Self.running()
        return await MainActor.run {
            running.filter { AppSearch.matches(string, name: $0.name, aliases: [], id: $0.id) }
        }
    }

    func suggestedEntities() async throws -> [ApplicationEntity] { await Self.running() }

    @MainActor private static func running() -> [ApplicationEntity] {
        RunningApplication.capture(showSystemApps: false)
            .filter { !$0.id.hasPrefix("com.apple.") }
            .map { ApplicationEntity(id: $0.id, name: $0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

enum LimitSwitchState: String, AppEnum {
    case on, off, toggle

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "intent.state.type"
    static let caseDisplayRepresentations: [LimitSwitchState: DisplayRepresentation] = [
        .on: "intent.state.on", .off: "intent.state.off", .toggle: "intent.state.toggle"
    ]
}

/// 打开、关闭或切换“启用限制”总开关。
struct SetLimitsIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.setLimits.title"
    static let description = IntentDescription("intent.setLimits.description")

    @Parameter(title: "intent.state.type", default: .toggle)
    var state: LimitSwitchState

    static var parameterSummary: some ParameterSummary { Summary("intent.setLimits.summary \(\.$state)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let value: Bool? = switch state { case .on: true; case .off: false; case .toggle: nil }
        return try await AutomationIntents.run(.setLimits(value))
    }
}

/// 在后台时临时暂停指定应用。
struct PauseApplicationIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.pause.title"
    static let description = IntentDescription("intent.pause.description")

    @Parameter(title: "intent.app.type")
    var application: ApplicationEntity

    @Parameter(title: "intent.pause.minutes", default: 60, inclusiveRange: (1, 240))
    var minutes: Int

    static var parameterSummary: some ParameterSummary { Summary("intent.pause.summary \(\.$application) \(\.$minutes)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await AutomationIntents.run(.pause(app: application.id, minutes: Double(minutes)))
    }
}

/// 立即恢复指定应用：取消临时暂停，规则正在限制时暂停执行一小时。
struct ResumeApplicationIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.resume.title"
    static let description = IntentDescription("intent.resume.description")

    @Parameter(title: "intent.app.type")
    var application: ApplicationEntity

    static var parameterSummary: some ParameterSummary { Summary("intent.resume.summary \(\.$application)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await AutomationIntents.run(.resume(app: application.id))
    }
}

@MainActor
enum AutomationIntents {
    static func run(_ command: AutomationCommand) async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await AutomationCenter.current().perform(command)
        guard outcome.succeeded else { throw AutomationError.failed(outcome.message) }
        return .result(dialog: IntentDialog(stringLiteral: outcome.message))
    }
}
