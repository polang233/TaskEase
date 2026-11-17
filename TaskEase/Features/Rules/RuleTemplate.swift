import Foundation

/// 规则模板的导入与导出。文件内容与偏好中的 rules.v1 相同：bundle identifier 到规则的 JSON 对象，
/// 旧版 `mode` 字段照常写入，旧版本与新版本可以互相读取。
enum RuleTemplate {
    enum Failure: LocalizedError {
        case unreadable
        case empty

        var errorDescription: String? {
            switch self {
            case .unreadable: String(localized: "template.error.unreadable")
            case .empty: String(localized: "template.error.empty")
            }
        }
    }

    struct Parsed: Equatable, Sendable {
        var rules: [String: AppRule]
        /// 被跳过的条目：系统应用、本应用或无效标识。
        var skipped: [String]
    }

    static let maximumCount = 500

    /// 导出时排序缩进，便于阅读与比较；内容与 rules.v1 一致。
    static func export(_ rules: [String: AppRule]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(rules.mapValues { $0.validated() })
    }

    /// 读取模板并校验数值；系统应用与本应用的条目跳过，与界面上的只读限制一致。
    static func parse(_ data: Data, ownID: String? = Bundle.main.bundleIdentifier) throws -> Parsed {
        let decoded: [String: AppRule]
        do { decoded = try StoredRules.decode(data) } catch { throw Failure.unreadable }
        guard decoded.count <= maximumCount else { throw Failure.unreadable }
        var result = Parsed(rules: [:], skipped: [])
        for (id, rule) in decoded {
            if isImportable(id, ownID: ownID) { result.rules[id] = rule } else { result.skipped.append(id) }
        }
        result.skipped.sort()
        guard !result.rules.isEmpty else { throw Failure.empty }
        return result
    }

    static func isImportable(_ id: String, ownID: String?) -> Bool {
        guard !id.isEmpty, id.count <= 255, id != ownID, !id.hasPrefix("com.apple.") else { return false }
        return id.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "-._".unicodeScalars.contains($0) }
    }
}
