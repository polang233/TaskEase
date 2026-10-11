import Foundation

/// 项目令牌只用于接收事件。加载时限制为 PostHog 的 HTTPS 接收域名。
struct PostHogConfiguration: Codable, Sendable {
    let projectID: Int
    let host: String
    let projectToken: String

    var endpoint: URL? {
        guard let url = URL(string: host), url.scheme == "https",
              ["us.i.posthog.com", "eu.i.posthog.com"].contains(url.host),
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil, ["", "/"].contains(url.path),
              projectToken.hasPrefix("phc_"), projectToken.count <= 256 else { return nil }
        return url.appendingPathComponent("i/v0/e/")
    }

    static func load(bundle: Bundle = .main) -> PostHogConfiguration? {
        guard let url = bundle.url(forResource: "PostHog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(Self.self, from: data), value.endpoint != nil else { return nil }
        return value
    }
}

protocol UsageSending: Sendable {
    func send(_ event: DailyUsageEvent) async throws
}

/// 直接调用 Capture API；临时会话不保留 cookies、响应缓存或认证凭据。
struct PostHogClient: UsageSending {
    let configuration: PostHogConfiguration
    let session: URLSession

    init(configuration: PostHogConfiguration, session: URLSession? = nil) {
        self.configuration = configuration
        let settings = URLSessionConfiguration.ephemeral
        settings.httpShouldSetCookies = false
        settings.urlCache = nil
        settings.urlCredentialStorage = nil
        settings.timeoutIntervalForRequest = 10
        settings.timeoutIntervalForResource = 15
        settings.httpMaximumConnectionsPerHost = 1
        self.session = session ?? URLSession(configuration: settings, delegate: NoAnalyticsRedirect(), delegateQueue: nil)
    }

    func request(for event: DailyUsageEvent) throws -> URLRequest {
        guard let endpoint = configuration.endpoint else { throw SendError.configuration }
        let properties: [String: Any] = [
            "app_version": event.appVersion, "app_build": event.appBuild,
            "os_name": "macOS", "os_version": event.osVersion,
            "region": event.region, "local_day": event.localDay, "is_test": event.isTest,
            "$process_person_profile": false, "$geoip_disable": true, "$ip": "0.0.0.0"
        ]
        let payload: [String: Any] = [
            "api_key": configuration.projectToken, "event": "taskease daily active",
            "distinct_id": event.installationID.uuidString, "uuid": event.id.uuidString,
            "timestamp": ISO8601DateFormatter().string(from: event.timestamp), "properties": properties
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("TaskEase/1", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return request
    }

    func send(_ event: DailyUsageEvent) async throws {
        try Task.checkCancellation()
        let (_, response) = try await session.data(for: request(for: event))
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw SendError.rejected
        }
    }

    enum SendError: Error { case configuration, rejected }
}

/// 统计请求不跟随重定向，避免携带事件数据转到其他接收方。
private final class NoAnalyticsRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
