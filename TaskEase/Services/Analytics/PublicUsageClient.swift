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

    /// PostHog 的公开页面携带双重 JSON 编码的缓存结果。只读取三张指定卡片：
    /// 人数（必需）、每日趋势与地区占比（可缺省），其余内容不解析也不保存。
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
              dashboard["id"] as? Int == 2_196_112, let tiles = dashboard["tiles"] as? [[String: Any]] else { throw LoadError.format }
        let insights = tiles.compactMap { $0["insight"] as? [String: Any] }
        func insight(_ id: String) -> [String: Any]? { insights.first { $0["short_id"] as? String == id } }

        guard let count = insight(Tile.count), let rows = count["result"] as? [[Any]], rows.count == 1, rows[0].count == 1,
              let total = integer(rows[0][0]) else { throw LoadError.format }
        let updatedAt = (count["last_refresh"] as? String).flatMap(date)
        var summary = PublicUsageSummary(activeInstallations: total, updatedAt: updatedAt)

        if let series = (insight(Tile.trend)?["result"] as? [[String: Any]])?.first,
           let days = series["days"] as? [String], let values = series["data"] as? [Any], days.count == values.count, days.count <= 400 {
            let parser = DateFormatter()
            parser.calendar = Calendar(identifier: .gregorian)
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.timeZone = TimeZone(identifier: "UTC")
            parser.dateFormat = "yyyy-MM-dd"
            summary.days = zip(days, values).compactMap { day, value in
                guard let date = parser.date(from: day), let count = integer(value) else { return nil }
                return .init(date: date, installations: count)
            }
        }
        if let rows = insight(Tile.regions)?["result"] as? [[Any]] {
            summary.regions = rows.compactMap { row -> PublicUsageSummary.Region? in
                guard row.count == 2, let name = row[0] as? String, !name.isEmpty, name.count <= 40,
                      let count = integer(row[1]) else { return nil }
                return .init(name: regionName(name), installations: count)
            }.sorted { $0.installations > $1.installations }.prefix(5).map { $0 }
        }
        return summary
    }

    /// 地区固定使用英文，兼容看板缓存中的旧中文标签。
    private static func regionName(_ value: String) -> String {
        let legacyNames = [
            "中国": "China", "CN": "China",
            "台湾": "Taiwan", "TW": "Taiwan",
            "香港": "Hong Kong", "HK": "Hong Kong",
            "澳门": "Macao", "MO": "Macao",
            "美国": "United States", "US": "United States",
            "日本": "Japan", "JP": "Japan",
            "韩国": "South Korea", "KR": "South Korea",
            "新加坡": "Singapore", "SG": "Singapore",
            "英国": "United Kingdom", "GB": "United Kingdom",
            "德国": "Germany", "DE": "Germany",
            "法国": "France", "FR": "France",
            "加拿大": "Canada", "CA": "Canada",
            "澳大利亚": "Australia", "AU": "Australia",
            "印度": "India", "IN": "India",
            "俄罗斯": "Russia", "RU": "Russia",
            "未知": "Unknown",
        ]
        if let name = legacyNames[value] { return name }
        if value == "unknown" { return "Unknown" }
        let english = Locale(identifier: "en")
        return english.localizedString(forRegionCode: value) ?? value
    }

    private enum Tile {
        static let count = "MfmaDUaP"
        static let trend = "8r3p40Y9"
        static let regions = "l1yAQ9JN"
    }

    /// 只接受合理范围内的非负整数，排除布尔值与小数。
    private static func integer(_ value: Any) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue <= 1_000_000_000,
              number.doubleValue.rounded(.towardZero) == number.doubleValue else { return nil }
        return number.intValue
    }

    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
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
