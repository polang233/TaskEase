import Foundation

/// 访问本项目公开仓库的只读 GitHub API；不登录、不保存令牌，供更新检查等功能共用。
struct GitHubClient: Sendable {
    static let shared = GitHubClient()
    static let repository = "polang233/TaskEase"

    struct Release: Decodable, Sendable {
        let tagName: String
        let name: String?
        let htmlURL: URL
        let publishedAt: Date?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name", name, htmlURL = "html_url", publishedAt = "published_at"
        }

        /// 去掉标签前缀 v，便于与 CFBundleShortVersionString 比较。
        var version: String { tagName.hasPrefix("v") || tagName.hasPrefix("V") ? String(tagName.dropFirst()) : tagName }
    }

    enum Failure: Error { case unavailable, rateLimited }

    private let session: URLSession

    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        self.session = session ?? URLSession(configuration: configuration)
    }

    /// 最新正式版本；仓库还没有发布时返回 nil。
    func latestRelease() async throws -> Release? {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("TaskEase/\(AppVersion.short)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw Failure.unavailable }
        switch http.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Release.self, from: data)
        case 404: return nil
        case 403, 429: throw Failure.rateLimited
        default: throw Failure.unavailable
        }
    }
}

/// 版本号按数字段比较，缺少的段视为 0；非数字后缀忽略。
enum VersionOrder {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = parts(candidate), b = parts(current)
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0, right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private static func parts(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
}
