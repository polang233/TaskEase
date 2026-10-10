import Foundation
import Testing
@testable import TaskEase

struct ApplicationRulesTests {
    @Test @MainActor func emptyRulesCannotEnableAndRemovingLastActiveRuleTurnsOff() {
        let model = AppModel(preview: true)
        defer { model.shutdown() }
        #expect(!model.canEnable)
        model.setEnabled(true)
        #expect(!model.enabled)
        model.setRule("example.browser", rule: AppRule(mode: .budget))
        #expect(model.canEnable)
        #expect(!model.enabled)
        model.setEnabled(true)
        #expect(model.enabled)
        model.resetRule("example.browser")
        #expect(!model.enabled)
        #expect(!model.canEnable)
        #expect(model.rules.isEmpty)
    }

    @Test @MainActor func savedRuleRemainsEditableAfterApplicationExits() {
        let model = AppModel(preview: true)
        defer { model.shutdown() }
        model.setRule("example.browser", rule: AppRule(mode: .budget, cpuPercent: 20, delaySeconds: 10))
        model.apply(MonitoringSnapshot(apps: [], system: nil))
        model.setApplicationList(.configured)
        let saved = model.selectedApp
        #expect(saved?.name == "网页浏览器")
        #expect(saved?.isRunning == false)
        #expect(saved?.status == .notRunning)
        #expect(saved.map(model.allowsRuleEditing) == true)
        model.setRule("example.browser", rule: AppRule(mode: .budget, cpuPercent: 35, delaySeconds: 20))
        #expect(model.rules["example.browser"]?.cpuPercent == 35)
        #expect(model.rules["example.browser"]?.delaySeconds == 20)
    }

    @Test @MainActor func keepingOriginalBehaviorPreservesEditedEntryUntilRemoved() {
        let model = AppModel(preview: true)
        defer { model.shutdown() }
        model.setRule("example.browser", rule: AppRule(mode: .budget))
        model.setEnabled(true)
        model.setRule("example.browser", rule: AppRule(mode: .off, cpuPercent: 35, delaySeconds: 12))
        #expect(!model.enabled)
        #expect(!model.canEnable)
        #expect(model.configuredApps.count == 1)
        #expect(model.rules["example.browser"]?.cpuPercent == 35)
        model.resetRule("example.browser")
        #expect(model.configuredApps.isEmpty)
    }

    @Test @MainActor func systemApplicationsAreHiddenByDefaultAndRemainReadOnly() {
        let model = AppModel(preview: true)
        defer { model.shutdown() }
        #expect(!model.filteredApps.contains { $0.id == "com.apple.finder" })
        model.updatePreferences { $0.showSystemApps = true }
        let finder = model.filteredApps.first { $0.id == "com.apple.finder" }
        #expect(finder != nil)
        #expect(finder.map(model.allowsRuleEditing) == false)
        model.setRule("com.apple.finder", rule: AppRule(mode: .budget))
        #expect(model.rules["com.apple.finder"] == nil)
    }

    @Test func userInstalledAppleApplicationIsVisibleInUserAppList() {
        #expect(!ApplicationScope.isSystem(id: "com.apple.dt.Xcode", roots: ["/Applications/Xcode.app"]))
        #expect(ApplicationScope.isSystem(id: "com.apple.finder", roots: ["/System/Library/CoreServices/Finder.app"]))
    }

    @Test func invisibleAndUnconfiguredApplicationHasNoPollingTimer() {
        #expect(SamplingPolicy.nextInterval(displayVisible: false, displayInterval: 2,
                                           controlMonitoring: false, waitingSeconds: []) == nil)
    }

    @Test func slowDisplayDoesNotDelayControlHeartbeatOrBackgroundDeadline() {
        #expect(SamplingPolicy.nextInterval(displayVisible: true, displayInterval: 10,
                                           controlMonitoring: false, waitingSeconds: []) == 10)
        #expect(SamplingPolicy.nextInterval(displayVisible: true, displayInterval: 10,
                                           controlMonitoring: true, waitingSeconds: []) == 2)
        #expect(SamplingPolicy.nextInterval(displayVisible: false, displayInterval: 10,
                                           controlMonitoring: true, waitingSeconds: [0.25]) == 0.25)
    }

    @Test @MainActor func controlRefreshPreservesVisibleMetricsUntilDisplayRefresh() throws {
        let model = AppModel(preview: true)
        defer { model.shutdown() }
        model.setRule("example.browser", rule: AppRule(mode: .budget))
        let before = try #require(model.apps.first { $0.id == "example.browser" })
        var fresh = before
        fresh.cpuPercent = 88
        fresh.memoryBytes = 2_000_000_000
        fresh.readRate = 9999
        model.apply(MonitoringSnapshot(apps: [fresh], system: nil), updateDisplay: false)
        let displayed = try #require(model.apps.first { $0.id == "example.browser" })
        #expect(displayed.cpuPercent == before.cpuPercent)
        #expect(displayed.memoryBytes == before.memoryBytes)
        #expect(displayed.readRate == before.readRate)
        #expect(displayed.network == before.network)
        #expect(displayed.processNetwork == before.processNetwork)
        #expect(model.apps.contains { $0.id == "example.editor" })
        model.apply(MonitoringSnapshot(apps: [fresh], system: nil))
        #expect(model.apps.first?.cpuPercent == 88)
        #expect(model.apps.first?.memoryBytes == 2_000_000_000)
    }

    @Test func samplerResetStartsAFreshCPUBaseline() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let own = RunningApplication(id: "example.sampler", name: "Sampler test",
                                     roots: [Bundle.main.bundleURL.path], primaryPIDs: [pid], isHidden: false)
        var sampler = ProcessSampler()
        let first = try #require(sampler.sample([own], includeSystem: false).apps.first)
        #expect(!first.samples.isEmpty)
        #expect(first.cpuPercent == nil)
        let second = try #require(sampler.sample([own], includeSystem: false).apps.first)
        #expect(second.cpuPercent != nil)
        sampler.reset()
        let reset = try #require(sampler.sample([own], includeSystem: false).apps.first)
        #expect(reset.cpuPercent == nil)
    }

    @Test func preferencesAndExistingRuleFormatRoundTrip() throws {
        let preferences = AppPreferences(showSystemApps: true, refreshInterval: .ten, theme: .dark)
        let data = try JSONEncoder().encode(preferences)
        #expect(try JSONDecoder().decode(AppPreferences.self, from: data) == preferences)
        let legacy = Data(#"{"app":{"mode":"gentle","cpuPercent":20,"delaySeconds":3}}"#.utf8)
        let rules = try StoredRules.decode(legacy)
        #expect(rules["app"]?.mode == .gentle)
        #expect(rules["app"]?.delaySeconds == 3)
        #expect(try StoredRules.decode(StoredRules.encode(rules)) == rules)
        #expect(AppRule(delaySeconds: 900).validated().delaySeconds == 300)
    }
    @Test func foregroundDisplayStopsPollingButKeepsControlDeadlines() {
        let paused = SamplingPolicy.shouldRefreshDisplay(managementVisible: true, menuVisible: false,
                                                        isForeground: false, onlyInForeground: true)
        #expect(!paused)
        #expect(SamplingPolicy.nextInterval(displayVisible: paused, displayInterval: 1,
                                           controlMonitoring: false, waitingSeconds: []) == nil)
        #expect(SamplingPolicy.nextInterval(displayVisible: paused, displayInterval: 1,
                                           controlMonitoring: true, waitingSeconds: []) == 2)
        #expect(SamplingPolicy.nextInterval(displayVisible: paused, displayInterval: 1,
                                           controlMonitoring: true, waitingSeconds: [0.2]) == 0.2)
        #expect(SamplingPolicy.shouldRefreshDisplay(managementVisible: true, menuVisible: false,
                                                   isForeground: true, onlyInForeground: true))
        #expect(SamplingPolicy.shouldRefreshDisplay(managementVisible: true, menuVisible: false,
                                                   isForeground: false, onlyInForeground: false))
        #expect(SamplingPolicy.shouldRefreshDisplay(managementVisible: false, menuVisible: true,
                                                   isForeground: false, onlyInForeground: true))
        #expect(!SamplingPolicy.shouldRefreshDisplay(managementVisible: false, menuVisible: false,
                                                    isForeground: true, onlyInForeground: false))
    }

    @Test func existingDisplayPreferencesKeepTheirValues() throws {
        let legacy = Data(#"{"showSystemApps":true,"refreshInterval":5,"theme":"dark"}"#.utf8)
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: legacy)
        #expect(preferences.showSystemApps)
        #expect(preferences.refreshInterval == .five)
        #expect(preferences.theme == .dark)
        #expect(preferences.refreshOnlyInForeground)
        var changed = preferences
        changed.refreshOnlyInForeground = false
        #expect(try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(changed)) == changed)
    }

}
