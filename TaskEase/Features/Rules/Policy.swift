import Foundation

/// 纯规则计算，统一确定应用当前状态和是否需要进程控制。
enum Policy {
    static func status(rule: AppRule, enabled: Bool, controllable: Bool,
                       isForeground: Bool, isHidden: Bool, backgroundSeconds: Double) -> RuleStatus {
        guard controllable else { return .unavailable }
        guard rule.isActive else { return .unmanaged }
        guard enabled else { return .paused }
        if !rule.alwaysLimit {
            guard !isForeground || isHidden else { return .foreground }
            guard backgroundSeconds >= rule.delaySeconds else { return .waiting }
        }
        // 状态按影响程度取最强的一项显示。
        if rule.suspends { return .suspended }
        if rule.limitsPerformance { return .budget }
        if rule.lowersPriority { return .gentle }
        return rule.volumePercent > 0 ? .quieted : .muted
    }
    static func shouldControl(_ status: RuleStatus) -> Bool {
        [.gentle, .budget, .suspended, .muted, .quieted].contains(status)
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
