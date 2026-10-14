import Foundation
import Testing
@testable import TaskEase

/// 公开页面可能调整格式；失效时显示不可用，不把解析失败当成零设备。
struct PublicUsageTests {
    private func page(_ value: Any, id: Int = 2_196_112, doubleEncoded: Bool = true) throws -> Data {
        let root: [String: Any] = ["dashboard": ["id": id, "tiles": [
            ["insight": ["short_id": "other", "result": [[999]]]],
            ["insight": ["short_id": "MfmaDUaP", "result": [[value]], "last_refresh": "2026-10-11T13:00:00.000Z"]]
        ]]]
        var json = try JSONSerialization.data(withJSONObject: root)
        if doubleEncoded { json = try JSONSerialization.data(withJSONObject: String(decoding: json, as: UTF8.self), options: .fragmentsAllowed) }
        return Data(("<script type=\"application/json\" id=\"posthog-exported-data\">" + String(decoding: json, as: UTF8.self) + "</script>").utf8)
    }

    @Test func publicCountSupportsJSONEncodingAndZero() throws {
        let summary = try PublicUsageClient.parse(page(42))
        #expect(summary.activeInstallations == 42)
        #expect(summary.updatedAt != nil)
        #expect(try PublicUsageClient.parse(page(0, doubleEncoded: false)).activeInstallations == 0)
    }

    @Test func trendAndRegionsAreOptionalAndBounded() throws {
        let root: [String: Any] = ["dashboard": ["id": 2_196_112, "tiles": [
            ["insight": ["short_id": "MfmaDUaP", "result": [[3]]]],
            ["insight": ["short_id": "8r3p40Y9", "result": [["days": ["2026-10-10", "2026-10-11"], "data": [1, 2]]]]],
            ["insight": ["short_id": "l1yAQ9JN", "result": [["中国", 2], ["日本", 1], ["", 5], ["坏数据", 1.5]]]]
        ]]]
        let json = try JSONSerialization.data(withJSONObject: root)
        let data = Data(("<script id=\"posthog-exported-data\">" + String(decoding: json, as: UTF8.self) + "</script>").utf8)
        let summary = try PublicUsageClient.parse(data)
        #expect(summary.days.map(\.installations) == [1, 2])
        #expect(summary.regions.map(\.name) == ["China", "Japan"])
        #expect(try PublicUsageClient.parse(page(7)).days.isEmpty)
    }

    @Test func malformedWrongDashboardAndNonCountsFail() throws {
        for data in [try page(-1), try page(1.2), try page(true), try page("42"), try page(1, id: 99), Data("login required".utf8)] {
            #expect(throws: (any Error).self) { try PublicUsageClient.parse(data) }
        }
    }

    @Test @MainActor func closingCancelsAndLateReplyCannotUpdateTheWindow() async throws {
        let pending = PendingSummary()
        let model = UsageStatisticsModel(loader: { _ in await pending.load() })
        model.refresh()
        await pending.waitUntilStarted()
        #expect(model.loading)
        model.cancel()
        #expect(!model.loading)
        await pending.complete()
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.summary == nil)
        #expect(!model.failed)
    }

    @Test @MainActor func previewStatisticsNeverCallTheNetwork() async {
        let model = UsageStatisticsModel(fixtures: true, loader: { _ in
            Issue.record("Preview attempted a network request")
            return .init(activeInstallations: 999, updatedAt: nil)
        })
        model.refresh(force: true)
        await Task.yield()
        #expect(model.summary?.activeInstallations == 18)
        #expect(!model.loading)
    }
}

private actor PendingSummary {
    private var response: CheckedContinuation<PublicUsageSummary, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func load() async -> PublicUsageSummary {
        await withCheckedContinuation { response = $0; started?.resume(); started = nil }
    }
    func waitUntilStarted() async {
        if response != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func complete() {
        response?.resume(returning: .init(activeInstallations: 99, updatedAt: nil))
        response = nil
    }
}
