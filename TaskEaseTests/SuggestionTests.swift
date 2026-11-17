import Foundation
import Testing
@testable import TaskEase

struct SuggestionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func baseline(cpu: Double, gpu: Double? = nil, compositing: Double = 0, seconds: TimeInterval = 120) -> UsageBaseline {
        var baseline = UsageBaseline(updatedAt: now)
        baseline.add(cpu: cpu, gpu: gpu, compositing: compositing, seconds: seconds, at: now)
        return baseline
    }

    @Test func busyBackgroundAppsAreSuggestedWithMethodByKind() {
        let baselines = [
            "remote": baseline(cpu: 8, gpu: 30, compositing: 25),
            "chat": baseline(cpu: 15, gpu: 1),
            "player": baseline(cpu: 12),
            "build": baseline(cpu: 60, gpu: 0),
            "quiet": baseline(cpu: 2, gpu: 1),
            "brief": baseline(cpu: 90, seconds: 30)
        ]
        let candidates = [
            SuggestionEngine.Candidate(id: "remote", name: "Remote Desktop", category: nil),
            SuggestionEngine.Candidate(id: "chat", name: "Chat", category: "public.app-category.social-networking"),
            SuggestionEngine.Candidate(id: "player", name: "Spotify", category: nil),
            SuggestionEngine.Candidate(id: "build", name: "Builder", category: "public.app-category.developer-tools"),
            SuggestionEngine.Candidate(id: "quiet", name: "Quiet", category: nil),
            SuggestionEngine.Candidate(id: "brief", name: "Brief", category: nil)
        ]
        let result = SuggestionEngine.suggestions(baselines: baselines, candidates: candidates, excluded: [],
                                                  settings: SuggestionSettings(), now: now)
        // 低于阈值与观察不足一分钟的应用不列出；按占用从高到低排列。
        #expect(result.map(\.id) == ["build", "remote", "chat", "player"])
        let methods = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0.method) })
        #expect(methods["remote"] == .pause)
        #expect(methods["chat"] == .lowerPriority)
        #expect(methods["player"] == .lowerPriority)
        #expect(methods["build"] == .limitCPU)
        #expect(result.first { $0.id == "remote" }?.compositingPercent == 25)
    }

    @Test func rulesDismissalsAndThresholdsFilterSuggestions() {
        let baselines = ["a": baseline(cpu: 12), "b": baseline(cpu: 30)]
        let candidates = [SuggestionEngine.Candidate(id: "a", name: "A", category: nil),
                          SuggestionEngine.Candidate(id: "b", name: "B", category: nil),
                          SuggestionEngine.Candidate(id: "c", name: "C", category: nil)]
        var settings = SuggestionSettings()
        #expect(SuggestionEngine.suggestions(baselines: baselines, candidates: candidates, excluded: ["b"],
                                             settings: settings, now: now).map(\.id) == ["a"])
        settings.dismissed = ["a"]
        #expect(SuggestionEngine.suggestions(baselines: baselines, candidates: candidates, excluded: [],
                                             settings: settings, now: now).map(\.id) == ["b"])
        settings.dismissed = []
        settings.cpuThreshold = 20
        #expect(SuggestionEngine.suggestions(baselines: baselines, candidates: candidates, excluded: [],
                                             settings: settings, now: now).map(\.id) == ["b"])
        // 过期基线不再给出建议。
        #expect(SuggestionEngine.suggestions(baselines: baselines, candidates: candidates, excluded: [],
                                             settings: settings, now: now.addingTimeInterval(20 * 86_400)).isEmpty)
    }

    @Test func suggestedRulesAreValidAndPauseNeverRunsAlways() {
        for method in SuggestedMethod.allCases {
            let rule = method.rule
            #expect(rule.isActive)
            #expect(rule.validated() == rule)
            #expect(!rule.alwaysLimit)
        }
        #expect(SuggestedMethod.pause.rule.suspends)
        #expect(SuggestedMethod.lowerPriority.rule.lowersPriority && !SuggestedMethod.lowerPriority.rule.limitsPerformance)
        #expect(SuggestedMethod.limitCPU.rule.cpuPercent == 20)
    }

    @Test func settingsDecodeOlderDataAndClampThresholds() throws {
        let decoded = try JSONDecoder().decode(SuggestionSettings.self, from: Data(#"{"dismissed":["x"]}"#.utf8))
        #expect(decoded.cpuThreshold == 10 && decoded.gpuThreshold == 5 && decoded.dismissed == ["x"])
        var settings = SuggestionSettings()
        settings.cpuThreshold = .infinity
        settings.gpuThreshold = 500
        #expect(settings.validated().cpuThreshold == 10)
        #expect(settings.validated().gpuThreshold == 100)
    }

    @MainActor @Test func applyingASuggestionCreatesTheRuleAndEnablesFirstRule() throws {
        let model = AppModel(preview: true)
        defer { model.shutdown() }
        // 预览夹具：网页浏览器后台 CPU 32%、GPU 8%。
        let suggestion = try #require(model.suggestions.first { $0.id == "example.browser" })
        #expect(!model.enabled)
        model.applySuggestion(suggestion)
        #expect(model.rules["example.browser"] == suggestion.method.rule)
        #expect(model.enabled)
        #expect(!model.suggestions.contains { $0.id == "example.browser" })
        // 用户主动关闭总开关后，再套用其他建议不会自动打开。
        model.setEnabled(false)
        if let next = model.suggestions.first {
            model.applySuggestion(next)
            #expect(!model.enabled)
        }
        model.suggestionCenter.dismiss("example.editor")
        #expect(!model.suggestions.contains { $0.id == "example.editor" })
        model.suggestionCenter.restoreDismissed()
        #expect(model.suggestionCenter.settings.dismissed.isEmpty)
    }
}
