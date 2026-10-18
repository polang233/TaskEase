import Foundation
import Testing
@testable import TaskEase

/// 使用合成计数和隔离模型验证网络归属、规则存储与权限状态。
struct NetworkingTests {
    @Test func CSVUsesHeaderAndLastPIDSeparator() throws {
        let counters = try NetworkCSV.parse(",bytes_out,bytes_in,\n\"A,B.name.101\",300,600,\nHelper.102,70,80,\n")
        #expect(counters[101] == NetworkByteCount(received: 600, sent: 300))
        #expect(counters[102] == NetworkByteCount(received: 80, sent: 70))
        #expect(throws: NetworkCSV.ParseError.self) { try NetworkCSV.parse("app.101,1,2") }
        #expect(throws: NetworkCSV.ParseError.self) { try NetworkCSV.parse(",bytes_in,bytes_out,\napp.101,abc,2,") }
        #expect(throws: NetworkCSV.ParseError.self) { try NetworkCSV.parse(",bytes_in,bytes_out,\napp.101,1,2,\napp.101,2,3,") }
    }

    private func app(pid: Int32, start: UInt64 = 1) -> AppReading {
        let identity = ProcessIdentity(pid: pid, uid: 501, startSeconds: start, startMicroseconds: 0)
        let sample = ProcessSample(identity: identity, parentPID: 1, status: 2, cpuTicks: 0,
                                   memoryBytes: 0, readBytes: 0, writeBytes: 0, wakeups: 0)
        return AppReading(id: "example.network", name: "Network", bundlePaths: [], primaryPIDs: [pid],
                          targets: [], samples: [sample], memoryBytes: 0, readRate: 0, writeRate: 0,
                          canControl: true, isHidden: false)
    }

    @Test func ratesAggregateMembersAndResetForReusedPIDs() throws {
        var sampler = NetworkRateSampler()
        var application = app(pid: 101)
        application.samples += app(pid: 102).samples
        let time = UInt64(NativeProcess.ticksPerSecond)
        let first = sampler.sample([application], counters: [101: .init(received: 100, sent: 200), 102: .init(received: 50, sent: 70)], now: time)
        #expect(first.applications[application.id]?.receiveRate == nil)
        let next = sampler.sample([application], counters: [101: .init(received: 300, sent: 500), 102: .init(received: 100, sent: 170)], now: time * 2)
        #expect(next.applications[application.id]?.receiveRate == 250)
        #expect(next.applications[application.id]?.sendRate == 400)
        #expect(next.processes[application.samples[0].identity]?.receiveRate == 200)
        let reused = app(pid: 101, start: 2)
        #expect(sampler.sample([reused], counters: [101: .init(received: 400, sent: 600)], now: time * 3)
            .applications[application.id]?.receiveRate == nil)
        #expect(sampler.sample([reused], counters: [101: .init(received: 1, sent: 1)], now: time * 4)
            .applications[application.id]?.receiveRate == nil)
        #expect(sampler.sample([reused], counters: [101: .init(received: 10, sent: 10)], now: time * 30)
            .applications[application.id]?.receiveRate == nil)
    }

    @Test func networkPermissionsAndScopeDetermineStatus() {
        let rule = NetworkRule(mode: .block, delaySeconds: 3)
        #expect(NetworkPolicy.status(rule: rule, enabled: true, controlAvailable: false, foreground: false, backgroundSeconds: 10) == .pendingExtension)
        #expect(NetworkPolicy.status(rule: rule, enabled: false, controlAvailable: true, foreground: false, backgroundSeconds: 10) == .paused)
        #expect(NetworkPolicy.status(rule: rule, enabled: true, controlAvailable: true, foreground: true, backgroundSeconds: 10) == .foreground)
        #expect(NetworkPolicy.status(rule: rule, enabled: true, controlAvailable: true, foreground: false, backgroundSeconds: 2) == .waiting)
        #expect(NetworkPolicy.status(rule: rule, enabled: true, controlAvailable: true, foreground: false, backgroundSeconds: 3) == .blocked)
        #expect(NetworkPolicy.status(rule: .init(mode: .limit, scope: .always), enabled: true, controlAvailable: true, foreground: true, backgroundSeconds: 0) == .limited)
    }

    @Test @MainActor func networkRulesRemainEditableOfflineAndSeparateFromCPU() throws {
        let model = AppModel(preview: true)
        defer { model.shutdown() }
        model.updatePreferences { $0.networkFeaturesEnabled = true }
        model.setNetworkRule("example.browser", rule: NetworkRule(mode: .limit, scope: .always))
        #expect(model.rules.isEmpty)
        #expect(model.savedRuleCount == 1)
        #expect(model.networkStatus(for: "example.browser") == .pendingExtension)
        #expect(!model.canEnable)
        model.apply(MonitoringSnapshot(apps: [], system: nil))
        model.setApplicationList(.configured)
        #expect(model.selectedApp?.name == "网页浏览器")
        #expect(model.selectedApp?.isRunning == false)
        model.updatePreferences { $0.networkFeaturesEnabled = true }
        model.setNetworkRule("example.browser", rule: .init(mode: .block))
        #expect(model.networkRules["example.browser"]?.mode == .block)
        model.resetRule("example.browser")
        #expect(model.configuredApps.isEmpty)
    }

    @Test @MainActor func removingNetworkRulePreservesCPURule() {
        let model = AppModel(preview: true)
        defer { model.shutdown() }
        model.setRule("example.browser", rule: .init(mode: .budget))
        model.updatePreferences { $0.networkFeaturesEnabled = true }
        model.setNetworkRule("example.browser", rule: .init(mode: .block))
        model.removeNetworkRule("example.browser")
        #expect(model.rules["example.browser"] == AppRule(mode: .budget))
        #expect(model.savedRuleCount == 1)
        #expect(model.networkRules.isEmpty)
    }

    @Test func bandwidthCreditIsSharedAndIdleBurstIsBounded() {
        var bucket = NetworkTokenBucket(kibPerSecond: 16)
        #expect(bucket.reserve(bytes: 16384, at: 0) == 0)
        #expect(bucket.reserve(bytes: 16384, at: 0) == 1)
        #expect(bucket.reserve(bytes: 16384, at: 0) == 2)
        #expect(bucket.reserve(bytes: 16384, at: 10) == 0)
        #expect(bucket.reserve(bytes: 16384, at: 10) == 1)
    }

    @Test func nativeSnapshotReaderRunsAndFinishes() async throws {
        let monitor = NetworkMonitor()
        let counters = await monitor.sample(pids: [ProcessInfo.processInfo.processIdentifier])
        #expect(counters != nil)
        let manyTargets = Set((2...260).map { Int32($0) })
        #expect(await monitor.sample(pids: manyTargets) != nil)
        await monitor.cancel()
        #expect(await monitor.sample(pids: []) == [:])
    }

    @Test func networkRuleValidationAndPersistenceRoundTrip() throws {
        let rule = NetworkRule(mode: .limit, scope: .always, delaySeconds: .nan,
                               downloadKiBPerSecond: -1, uploadKiBPerSecond: Int.max).validated()
        #expect(rule.delaySeconds == 3)
        #expect(rule.downloadKiBPerSecond == 16)
        #expect(rule.uploadKiBPerSecond == 102400)
        #expect(try JSONDecoder().decode(NetworkRule.self, from: JSONEncoder().encode(rule)) == rule)
        #expect(!AppPreferences().networkActivityVisible)
        #expect(!AppPreferences().networkFeaturesEnabled)
    }

    @Test @MainActor func disablingExperimentHidesNetworkEntriesAndPreservesRules() {
        let model = AppModel(preview: true)
        defer { model.shutdown() }
        model.updatePreferences { $0.networkFeaturesEnabled = true }
        model.setNetworkRule("example.browser", rule: .init(mode: .block))
        #expect(model.preferences.networkActivityVisible)
        #expect(model.savedRuleCount == 1)
        model.updatePreferences { $0.networkFeaturesEnabled = false }
        #expect(!model.preferences.networkActivityVisible)
        #expect(model.configuredApps.isEmpty)
        #expect(model.networkRules["example.browser"]?.mode == .block)
        model.updatePreferences { $0.networkFeaturesEnabled = true }
        #expect(model.savedRuleCount == 1)
    }
}
