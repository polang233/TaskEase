import Foundation

/// 显式执行的接入核验，仅发送标为样例的事件，不读取用户统计配置。
@MainActor
enum AnalyticsCheck {
    static func run() -> Bool {
        guard let configuration = PostHogConfiguration.load() else {
            print("Analytics configuration unavailable")
            return false
        }
        let event = DailyUsageEvent(id: UUID(), installationID: UUID(), timestamp: Date(),
            localDay: "2026-10-11", appVersion: "1.1.0", appBuild: "2", osVersion: "27.0.1",
            region: "example", isTest: true)
        var outcome: Bool?
        let task = Task { @MainActor in
            do {
                try await PostHogClient(configuration: configuration).send(event)
                outcome = true
            } catch { outcome = false }
        }
        let deadline = Date().addingTimeInterval(20)
        while outcome == nil && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        task.cancel()
        print(outcome == true ? "PostHog sample event accepted; is_test=true" : "PostHog sample event was not accepted")
        return outcome == true
    }
}
