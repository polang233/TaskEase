import Foundation

/// 纯规则计算，统一确定应用当前状态和是否需要进程控制。
enum Policy {
    static func status(rule: AppRule, enabled: Bool, controllable: Bool,
                       isForeground: Bool, isHidden: Bool, backgroundSeconds: Double) -> RuleStatus {
        guard controllable else { return .unavailable }
        guard rule.mode != .off else { return .unmanaged }
        guard enabled else { return .paused }
        guard !isForeground || isHidden else { return .foreground }
        guard backgroundSeconds >= rule.delaySeconds else { return .waiting }
        return rule.mode == .gentle ? .gentle : .budget
    }
    static func shouldControl(_ status: RuleStatus) -> Bool {
        status == .gentle || status == .budget
    }
}

enum StoredRules {
    static func decode(_ data: Data) throws -> [String: AppRule] {
        try JSONDecoder().decode([String: AppRule].self, from: data).mapValues { $0.validated() }
    }
    static func encode(_ rules: [String: AppRule]) throws -> Data {
        try JSONEncoder().encode(rules.mapValues { $0.validated() })
    }
}
