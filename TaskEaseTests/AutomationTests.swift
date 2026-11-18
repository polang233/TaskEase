import Foundation
import Testing
@testable import TaskEase

struct AutomationTests {
    @Test func temporaryPauseAppliesOnlyInBackgroundWhileEnabled() {
        let pause = TemporaryAction.pause(until: Date().addingTimeInterval(60))
        func status(_ rule: AppRule = AppRule(), enabled: Bool = true, foreground: Bool = false, hidden: Bool = false,
                    controllable: Bool = true, temporary: TemporaryAction?) -> RuleStatus {
            Policy.status(rule: rule, enabled: enabled, controllable: controllable, isForeground: foreground,
                          isHidden: hidden, backgroundSeconds: 0, temporary: temporary)
        }
        // 没有规则也能临时暂停，且不等待；总开关关闭时完全不控制。
        #expect(status(temporary: pause) == .held)
        #expect(status(enabled: false, temporary: pause) == .unmanaged)
        #expect(status(AppRule(mode: .suspend), enabled: false, temporary: pause) == .paused)
        #expect(Policy.shouldControl(.held))
        // 切回前台照常使用，隐藏后再次暂停。
        #expect(status(foreground: true, temporary: pause) == .foreground)
        #expect(status(foreground: true, hidden: true, temporary: pause) == .held)
        // 系统应用等不可控制的应用不受影响。
        #expect(status(controllable: false, temporary: pause) == .unavailable)
        // 立即恢复只在规则会执行时生效，否则照常显示。
        let release = TemporaryAction.release(until: Date().addingTimeInterval(60))
        #expect(status(AppRule(mode: .suspend), enabled: true, temporary: release) == .released)
        #expect(!Policy.shouldControl(.released))
        #expect(status(AppRule(mode: .suspend), enabled: false, temporary: release) == .paused)
        #expect(status(temporary: release) == .unmanaged)
    }

    @MainActor @Test func masterSwitchFullyStopsTemporaryActions() {
        let model = AppModel(preview: true)
        defer { model.shutdown() }
        #expect(!model.enabled)
        // 总开关关闭时临时暂停会一并打开它。
        #expect(model.pauseTemporarily("example.browser"))
        #expect(model.enabled)
        #expect(model.apps.first { $0.id == "example.browser" }?.status == .held)
        // 关闭总开关：临时暂停全部结束，应用恢复。
        model.setEnabled(false)
        #expect(model.temporaryActions.isEmpty)
        #expect(model.apps.first { $0.id == "example.browser" }?.status == .unmanaged)
        // 只为临时暂停打开的总开关，在暂停结束且没有规则时自动关闭。
        #expect(model.pauseTemporarily("example.browser"))
        #expect(model.resumeNow("example.browser"))
        #expect(!model.enabled)
    }

    @Test func temporaryMinutesAreClamped() {
        #expect(TemporaryAction.clampedMinutes(0) == 1)
        #expect(TemporaryAction.clampedMinutes(10_000) == 240)
        #expect(TemporaryAction.clampedMinutes(.nan) == 60)
        #expect(TemporaryAction.clampedMinutes(14.6) == 15)
    }

    @MainActor @Test func pauseResumeAndShutdownThroughTheModel() throws {
        let model = AppModel(preview: true)
        defer { model.shutdown() }
        // 预览中前台是代码编辑器，网页浏览器在后台。
        #expect(model.pauseTemporarily("example.browser", minutes: 30))
        #expect(model.temporaryActions["example.browser"]?.isPause == true)
        #expect(model.apps.first { $0.id == "example.browser" }?.status == .held)
        #expect(model.pauseTemporarily("example.editor"))
        #expect(model.apps.first { $0.id == "example.editor" }?.status == .foreground)
        #expect(!model.pauseTemporarily("com.apple.finder"))
        #expect(!model.pauseTemporarily("example.missing"))
        // 没有规则时立即恢复直接结束临时暂停。
        #expect(model.resumeNow("example.browser"))
        #expect(model.temporaryActions["example.browser"] == nil)
        #expect(model.apps.first { $0.id == "example.browser" }?.status == .unmanaged)
        // 规则正在限制时，立即恢复让规则暂停执行。
        model.setRule("example.browser", rule: AppRule(mode: .budget, delaySeconds: 0, alwaysLimit: true))
        model.setEnabled(true)
        #expect(model.apps.first { $0.id == "example.browser" }?.status == .budget)
        #expect(model.resumeNow("example.browser"))
        #expect(model.apps.first { $0.id == "example.browser" }?.status == .released)
        model.clearTemporaryAction("example.browser")
        #expect(model.apps.first { $0.id == "example.browser" }?.status == .budget)
        #expect(!model.resumeNow("example.editor") || model.temporaryActions["example.editor"] == nil)
        // 退出时临时操作全部结束。
        #expect(model.pauseTemporarily("example.browser"))
        model.shutdown()
        #expect(model.temporaryActions.isEmpty)
    }

    @MainActor @Test func applicationExitEndsTemporaryActions() {
        let model = AppModel(preview: true)
        defer { model.shutdown() }
        #expect(model.pauseTemporarily("example.browser"))
        model.apply(MonitoringSnapshot(apps: AppModel.exampleApps.filter { $0.id != "example.browser" }, system: nil))
        #expect(model.temporaryActions["example.browser"] == nil)
    }

    @MainActor @Test func menuRowsKeepTemporarilyPausedAppsReachable() {
        var apps = (0..<7).map { index in
            AppReading(id: "app\(index)", name: "App \(index)", bundlePaths: [], primaryPIDs: [], targets: [], samples: [],
                       cpuPercent: Double(100 - index), memoryBytes: 0, readRate: 0, writeRate: 0, canControl: true, isHidden: false)
        }
        apps[6].cpuPercent = 0
        let rows = QuickActions.rows(apps, sortedBy: .cpu, temporary: ["app6": .pause(until: Date().addingTimeInterval(60))])
        #expect(rows.map(\.id) == ["app0", "app1", "app2", "app3", "app4", "app6"])
        #expect(QuickActions.rows(apps, sortedBy: .cpu, temporary: [:]).count == 5)
    }

    @Test func urlSchemeCommandsParse() throws {
        func parse(_ text: String) -> AutomationCommand? { URL(string: text).flatMap(AutomationCommand.parse) }
        #expect(parse("taskease://enable") == .setLimits(true))
        #expect(parse("taskease://disable") == .setLimits(false))
        #expect(parse("TaskEase://Toggle") == .setLimits(nil))
        #expect(parse("taskease:toggle") == .setLimits(nil))
        #expect(parse("taskease://pause?app=com.example.remote") == .pause(app: "com.example.remote", minutes: 60))
        #expect(parse("taskease://pause?app=com.example.remote&minutes=999") == .pause(app: "com.example.remote", minutes: 240))
        #expect(parse("taskease://resume?app=com.example.remote") == .resume(app: "com.example.remote"))
        #expect(parse("taskease://pause") == nil)
        #expect(parse("taskease://delete-everything") == nil)
        #expect(parse("https://pause?app=com.example.remote") == nil)
    }

    @MainActor @Test func automationCommandsReportOutcomes() {
        let model = AppModel(preview: true)
        defer { model.shutdown() }
        #expect(!model.perform(.setLimits(true)).succeeded)
        #expect(!model.enabled)
        #expect(model.perform(.pause(app: "example.browser", minutes: 5)).succeeded)
        #expect(model.perform(.resume(app: "example.browser")).succeeded)
        #expect(!model.perform(.resume(app: "example.browser")).succeeded)
        #expect(!model.perform(.pause(app: "com.apple.finder", minutes: 5)).succeeded)
        model.setRule("example.browser", rule: AppRule(mode: .budget))
        #expect(model.perform(.setLimits(nil)).succeeded)
        #expect(model.enabled)
        #expect(model.perform(.setLimits(false)).succeeded)
        #expect(!model.enabled)
    }

    @Test func ruleTemplatesMatchStoredRulesAndSkipProtectedApps() throws {
        let rules = ["com.example.remote": AppRule(mode: .suspend, delaySeconds: 5),
                     "com.example.chat": AppRule(isEnabled: true, limitsPerformance: false, lowersPriority: true)]
        let exported = try RuleTemplate.export(rules)
        // 导出内容可直接作为 rules.v1 读取，并含旧版 mode 字段。
        #expect(try StoredRules.decode(exported) == rules.mapValues { $0.validated() })
        let object = try JSONSerialization.jsonObject(with: exported) as? [String: [String: Any]]
        #expect(object?["com.example.remote"]?["mode"] as? String == "suspend")
        let parsed = try RuleTemplate.parse(exported, ownID: "com.github.polang233.TaskEase")
        #expect(parsed.rules == rules.mapValues { $0.validated() })
        #expect(parsed.skipped.isEmpty)
        // 旧版只含 mode 的规则同样可以导入；系统应用、本应用与无效标识跳过。
        let legacy = Data(#"""
        {"com.example.old":{"mode":"budget","cpuPercent":900,"delaySeconds":3},
         "com.apple.Safari":{"mode":"suspend","cpuPercent":20,"delaySeconds":3},
         "com.github.polang233.TaskEase":{"mode":"budget","cpuPercent":20,"delaySeconds":3},
         "bad id/../x":{"mode":"budget","cpuPercent":20,"delaySeconds":3}}
        """#.utf8)
        let imported = try RuleTemplate.parse(legacy, ownID: "com.github.polang233.TaskEase")
        #expect(imported.rules.keys.sorted() == ["com.example.old"])
        #expect(imported.rules["com.example.old"]?.cpuPercent == 200)
        #expect(imported.skipped.count == 3)
        #expect(throws: RuleTemplate.Failure.self) { try RuleTemplate.parse(Data("[1,2]".utf8)) }
        #expect(throws: RuleTemplate.Failure.self) {
            try RuleTemplate.parse(Data(#"{"com.apple.Safari":{"mode":"budget","cpuPercent":20,"delaySeconds":3}}"#.utf8))
        }
    }

    @MainActor @Test func importingRulesMergesWithoutTurningLimitsOn() throws {
        let model = AppModel(preview: true)
        defer { model.shutdown() }
        model.setRule("example.editor", rule: AppRule(mode: .gentle))
        let data = try RuleTemplate.export(["example.browser": AppRule(mode: .suspend),
                                            "com.example.offline": AppRule(mode: .budget, cpuPercent: 40)])
        let result = try model.importRules(data)
        #expect(result.rules.count == 2)
        #expect(model.rules["example.browser"]?.suspends == true)
        #expect(model.rules["example.editor"]?.lowersPriority == true)
        #expect(model.rules["com.example.offline"]?.cpuPercent == 40)
        #expect(!model.enabled)
        #expect(model.configuredApps.contains { $0.id == "com.example.offline" && !$0.isRunning })
        #expect(try RuleTemplate.parse(model.exportRules()).rules.count == 3)
    }
}
