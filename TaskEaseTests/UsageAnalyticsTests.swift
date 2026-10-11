import Foundation
import Testing
@testable import TaskEase

/// 统计验证使用隔离偏好域、固定时间与本地传输夹具，不向服务端发送事件。
struct UsageAnalyticsTests {
    private var calendar: Calendar { DailyUsageSchedule.calendar(timeZone: TimeZone(identifier: "Asia/Taipei")!) }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test func firstActivitySendsAndRecentSuccessIsDeduplicated() {
        let morning = date("2026-10-11T03:59:00Z")
        let noon = date("2026-10-11T04:00:00Z")
        #expect(DailyUsageSchedule.action(now: morning, state: .init(), calendar: calendar) == .send)
        #expect(DailyUsageSchedule.action(now: noon, state: .init(), calendar: calendar) == .send)
        #expect(DailyUsageSchedule.action(now: noon.addingTimeInterval(60), state: .init(lastSuccess: noon), calendar: calendar)
            == .wait(date("2026-10-11T10:00:00Z")))
        #expect(DailyUsageSchedule.action(now: morning, state: .init(lastSuccess: noon), calendar: calendar) != .send)
    }

    @Test func retryIsBoundedAndEventRemainsStable() throws {
        let noon = date("2026-10-11T04:00:00Z")
        let event = DailyUsageEvent.capture(installationID: UUID(), now: noon, calendar: calendar)
        let retry = noon.addingTimeInterval(DailyUsageSchedule.retryInterval)
        let state = DailyUsageState(pending: event, attempts: 1, retryAfter: retry)
        #expect(DailyUsageSchedule.action(now: noon, state: state, calendar: calendar) == .wait(retry))
        #expect(DailyUsageSchedule.action(now: retry, state: state, calendar: calendar) == .send)
        let capped = DailyUsageState(pending: event, attempts: 3)
        #expect(DailyUsageSchedule.action(now: retry, state: capped, calendar: calendar) == .wait(date("2026-10-11T10:00:00Z")))
        #expect(DailyUsageSchedule.action(now: date("2026-10-11T10:00:00Z"), state: capped, calendar: calendar) == .send)
        #expect(DailyUsageSchedule.action(now: date("2026-10-12T04:00:00Z"), state: capped, calendar: calendar) == .send)
        #expect(try JSONDecoder().decode(DailyUsageState.self, from: JSONEncoder().encode(state)) == state)
    }

    @Test func heartbeatAndLocalDayBoundaryRespectTimezoneAndDST() {
        let us = DailyUsageSchedule.calendar(timeZone: TimeZone(identifier: "America/New_York")!)
        let last = date("2026-03-08T04:00:00Z")
        #expect(DailyUsageSchedule.action(now: last, state: .init(lastSuccess: last), calendar: us)
            == .wait(date("2026-03-08T05:00:00Z")))
        #expect(DailyUsageSchedule.action(now: date("2026-03-08T05:00:00Z"), state: .init(lastSuccess: last), calendar: us) == .send)
        let morning = date("2026-10-11T01:00:00Z")
        #expect(DailyUsageSchedule.action(now: morning.addingTimeInterval(21600), state: .init(lastSuccess: morning), calendar: calendar) == .send)
        #expect(DailyUsageSchedule.day(date("2026-10-11T16:30:00Z"), calendar: calendar) == "2026-10-12")
    }

    @Test func payloadHasOnlyDocumentedFieldsAndAnonymousProcessing() throws {
        let config = PostHogConfiguration(projectID: 1, host: "https://us.i.posthog.com", projectToken: "phc_fixture")
        let event = DailyUsageEvent.capture(installationID: UUID(), now: date("2026-10-11T04:00:00Z"), calendar: calendar,
                                           usage: UsageContext(cpuRuleCount: 2, networkRuleCount: 1, managementEnabled: true))
        let client = PostHogClient(configuration: config)
        let request = try client.request(for: event)
        let body = try #require(request.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let properties = try #require(payload["properties"] as? [String: Any])
        #expect(Set(properties.keys) == ["app_version", "app_build", "os_name", "os_version", "region", "local_day", "is_test", "$process_person_profile", "$geoip_disable", "$ip", "language", "time_zone", "cpu_rule_count", "network_rule_count", "management_enabled", "theme", "refresh_seconds", "network_display_enabled", "foreground_refresh_only"])
        #expect(properties["cpu_rule_count"] as? Int == 2)
        #expect(properties["time_zone"] as? String == "Asia/Taipei")
        #expect(properties["$process_person_profile"] as? Bool == false)
        #expect(properties["$geoip_disable"] as? Bool == true)
        #expect(properties["$ip"] as? String == "0.0.0.0")
        #expect(payload["uuid"] as? String == event.id.uuidString)
        #expect(payload["distinct_id"] as? String == event.installationID.uuidString)
        #expect(try client.request(for: event).httpBody == request.httpBody)
        #expect(request.url?.absoluteString == "https://us.i.posthog.com/i/v0/e/")
    }

    @Test func rejectsUnexpectedReceiverOrAdministrativeKey() {
        #expect(PostHogConfiguration(projectID: 1, host: "http://us.i.posthog.com", projectToken: "phc_fixture").endpoint == nil)
        #expect(PostHogConfiguration(projectID: 1, host: "https://example.com", projectToken: "phc_fixture").endpoint == nil)
        #expect(PostHogConfiguration(projectID: 1, host: "https://us.i.posthog.com", projectToken: "phx_private").endpoint == nil)
    }

    @Test func HTTPTransportReportsAcceptedAndRejectedResponses() async throws {
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [AnalyticsResponseFixture.self]
        let session = URLSession(configuration: settings)
        defer { session.invalidateAndCancel() }
        let client = PostHogClient(configuration: .init(projectID: 1, host: "https://us.i.posthog.com",
                                                       projectToken: "phc_fixture"), session: session)
        let accepted = DailyUsageEvent(id: UUID(), installationID: UUID(), timestamp: Date(), localDay: "2026-10-11",
            appVersion: "fixture", appBuild: "1", osVersion: "fixture", region: "accepted", isTest: true)
        try await client.send(accepted)
        let rejected = DailyUsageEvent(id: UUID(), installationID: UUID(), timestamp: Date(), localDay: "2026-10-11",
            appVersion: "fixture", appBuild: "1", osVersion: "fixture", region: "rejected", isTest: true)
        await #expect(throws: PostHogClient.SendError.self) { try await client.send(rejected) }
    }

    @Test @MainActor func disabledAndFixtureModesHaveNoScheduledWork() async throws {
        let name = "TaskEase.AnalyticsTest." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "usageAnalytics.enabled")
        let sender = MockUsageSender()
        let service = UsageAnalytics(defaults: defaults, sender: sender, observesSystem: false)
        #expect(!service.enabled)
        #expect(!service.hasScheduledTimer)
        #expect(defaults.data(forKey: "usageAnalytics.v1") == nil)
        let fixture = UsageAnalytics(fixtures: true, defaults: defaults, sender: sender)
        fixture.setEnabled(true)
        fixture.reconcile()
        #expect(!fixture.hasScheduledTimer)
        #expect(await sender.events.isEmpty)
        #expect(defaults.data(forKey: "usageAnalytics.v1") == nil)
        service.stop(); fixture.stop()
    }

    @Test @MainActor func successIsPersistedAndRepeatedTriggersDoNotSendAgain() async throws {
        let name = "TaskEase.AnalyticsTest." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let noon = Calendar.current.date(bySettingHour: 12, minute: 1, second: 0, of: Date())!
        let sender = MockUsageSender()
        let service = UsageAnalytics(defaults: defaults, sender: sender, observesSystem: false, clock: { noon })
        service.setEnabled(true)
        for _ in 0..<50 { if service.lastSuccess != nil { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(service.lastSuccess != nil)
        service.reconcile(); service.reconcile()
        #expect(await sender.events.count == 1)
        service.setEnabled(false)
        #expect(!service.hasScheduledTimer)
        let restored = UsageAnalytics(defaults: defaults, sender: sender, observesSystem: false, clock: { noon })
        restored.setEnabled(true)
        #expect(await sender.events.count == 1)
        #expect(restored.lastSuccess == service.lastSuccess)
        restored.stop()
    }

    @Test @MainActor func failurePersistsStableRetryAndDisablingStopsIt() async throws {
        let name = "TaskEase.AnalyticsTest." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let noon = Calendar.current.date(bySettingHour: 12, minute: 1, second: 0, of: Date())!
        let sender = MockUsageSender(fails: true)
        let service = UsageAnalytics(defaults: defaults, sender: sender, observesSystem: false, clock: { noon })
        service.setEnabled(true)
        for _ in 0..<50 { if service.hasScheduledTimer { break }; try await Task.sleep(for: .milliseconds(10)) }
        let data = try #require(defaults.data(forKey: "usageAnalytics.v1"))
        let state = try JSONDecoder().decode(DailyUsageState.self, from: data)
        #expect(state.attempts == 1)
        #expect(state.pending != nil)
        #expect(service.lastSuccess == nil)
        service.reconcile()
        #expect(await sender.events.count == 1)
        service.setEnabled(false)
        #expect(!service.hasScheduledTimer)
    }

    @Test @MainActor func cleanupAndQueuedWakeCannotRecreateData() async throws {
        let name = "TaskEase.AnalyticsTest." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let noon = Calendar.current.date(bySettingHour: 12, minute: 1, second: 0, of: Date())!
        let sender = DelayedUsageSender()
        let service = UsageAnalytics(defaults: defaults, sender: sender, observesSystem: false, clock: { noon })
        service.setEnabled(true)
        service.stop()
        defaults.removePersistentDomain(forName: name)
        service.wake(); service.reconcile()
        try await Task.sleep(for: .milliseconds(100))
        #expect(defaults.data(forKey: "usageAnalytics.v1") == nil)
        #expect(!service.hasScheduledTimer)
    }

    @Test func previousPendingEventsDecodeWithoutNewFields() throws {
        let event = DailyUsageEvent.capture(installationID: UUID(), now: Date(), calendar: calendar)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
        for key in ["language", "timeZone", "usage"] { object.removeValue(forKey: key) }
        let restored = try JSONDecoder().decode(DailyUsageEvent.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.id == event.id)
        #expect(restored.language == nil && restored.timeZone == nil && restored.usage == nil)
    }

    @Test @MainActor func deferredStartupCapturesLoadedConfiguration() async throws {
        let name = "TaskEase.AnalyticsTest." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "usageAnalytics.enabled")
        let sender = MockUsageSender()
        let service = UsageAnalytics(defaults: defaults, sender: sender, observesSystem: false, deferStart: true)
        #expect(await sender.events.isEmpty)
        service.activate { UsageContext(cpuRuleCount: 3, managementEnabled: true) }
        for _ in 0..<50 { if service.lastSuccess != nil { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(await sender.events.first?.usage?.cpuRuleCount == 3)
        service.stop()
    }

    @Test @MainActor func newInstallDefaultsOnAndExplicitOptOutPersists() throws {
        let name = "TaskEase.AnalyticsTest." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let sender = MockUsageSender()
        let fresh = UsageAnalytics(defaults: defaults, sender: sender, observesSystem: false, deferStart: true)
        #expect(fresh.enabled)
        fresh.setEnabled(false)
        let restored = UsageAnalytics(defaults: defaults, sender: sender, observesSystem: false, deferStart: true)
        #expect(!restored.enabled)
        #expect(!restored.hasScheduledTimer)
        fresh.stop(); restored.stop()
    }
}

private actor MockUsageSender: UsageSending {
    private(set) var events: [DailyUsageEvent] = []
    let fails: Bool
    init(fails: Bool = false) { self.fails = fails }
    func send(_ event: DailyUsageEvent) async throws {
        events.append(event)
        if fails { throw URLError(.notConnectedToInternet) }
    }
}

private actor DelayedUsageSender: UsageSending {
    func send(_ event: DailyUsageEvent) async throws { try await Task.sleep(for: .seconds(1)) }
}

/// URLProtocol 只返回合成响应，验证 HTTP 边界时不进行网络连接。
private final class AnalyticsResponseFixture: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let stream = request.httpBodyStream
        stream?.open()
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = stream?.read(&bytes, maxLength: bytes.count) ?? 0
        stream?.close()
        let body = request.httpBody ?? Data(bytes.prefix(max(0, count)))
        let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let properties = payload?["properties"] as? [String: Any]
        let code = properties?["region"] as? String == "accepted" ? 200 : 503
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("1".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
