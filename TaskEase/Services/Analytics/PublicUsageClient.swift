import Foundation

/// 读取已公开看板的缓存数字，应用内无需保存查询密钥或登录会话。
struct PublicUsageClient: Sendable {
    let session: URLSession

    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        self.session = session ?? URLSession(configuration: configuration, delegate: PublicUsageRedirect(), delegateQueue: nil)
    }

    func load() async throws -> PublicUsageSummary {
        let (data, response) = try await session.data(from: ProjectLinks.statistics)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 2_000_000 else {
            throw LoadError.unavailable
        }
        return try Self.parse(data)
    }

    /// PostHog 的公开页面携带双重 JSON 编码的缓存结果，只解析指定统计卡片。
    static func parse(_ data: Data) throws -> PublicUsageSummary {
        guard let html = String(data: data, encoding: .utf8) else { throw LoadError.format }
        let regex = try NSRegularExpression(pattern: #"<script\b(?=[^>]*\bid=["']posthog-exported-data["'])[^>]*>(.*?)</script>"#,
                                            options: [.dotMatchesLineSeparators, .caseInsensitive])
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range), let content = Range(match.range(at: 1), in: html) else {
            throw LoadError.format
        }
        var object = try JSONSerialization.jsonObject(with: Data(html[content].utf8), options: .fragmentsAllowed)
        if let encoded = object as? String { object = try JSONSerialization.jsonObject(with: Data(encoded.utf8)) }
        guard let root = object as? [String: Any], let dashboard = root["dashboard"] as? [String: Any],
              dashboard["id"] as? Int == 2_196_112, let tiles = dashboard["tiles"] as? [[String: Any]],
              let insight = tiles.compactMap({ $0["insight"] as? [String: Any] }).first(where: { $0["short_id"] as? String == "MfmaDUaP" }),
              let rows = insight["result"] as? [[Any]], rows.count == 1, rows[0].count == 1,
              let number = rows[0][0] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue <= 1_000_000_000,
              number.doubleValue.rounded(.towardZero) == number.doubleValue else { throw LoadError.format }
        let updatedAt = (insight["last_refresh"] as? String).flatMap { text -> Date? in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
        }
        return .init(activeInstallations: number.intValue, updatedAt: updatedAt)
    }

    enum LoadError: Error { case unavailable, format }
}

/// 公开看板读取不向其他域跟随重定向。
private final class PublicUsageRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

/// 仅内存缓存，不安排后台定时器；请求由统计窗口模型管理与取消。
actor PublicUsageCache {
    static let shared = PublicUsageCache()
    private var summary: PublicUsageSummary?
    private var fetchedAt: Date?
    private let client = PublicUsageClient()

    func load(refresh: Bool = false) async throws -> PublicUsageSummary {
        if !refresh, let summary, let fetchedAt {
            let age = Date().timeIntervalSince(fetchedAt)
            if age >= 0 && age < 1800 { return summary }
        }
        let value = try await client.load()
        try Task.checkCancellation()
        summary = value
        fetchedAt = Date()
        return value
    }
}
