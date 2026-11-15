import Foundation

/// 纯规则计算，统一确定应用当前状态和是否需要进程控制。
enum Policy {
    static func status(rule: AppRule, enabled: Bool, controllable: Bool,
                       isForeground: Bool, isHidden: Bool, backgroundSeconds: Double,
                       temporary: TemporaryAction? = nil) -> RuleStatus {
        guard controllable else { return .unavailable }
        // 临时暂停与总开关、规则无关，只在后台生效且不等待；切回前台照常使用，再次离开立即暂停，直到期限。
        switch temporary {
        case .pause:
            return isForeground && !isHidden ? .foreground : .held
        case .release where rule.isActive && enabled:
            return .released
        default:
            break
        }
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
        [.gentle, .budget, .suspended, .muted, .quieted, .held].contains(status)
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
