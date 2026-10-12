import Foundation

/// 网络配置单独保存，保留原有 CPU 规则的格式与启用状态。
enum NetworkRuleMode: String, Codable, CaseIterable, Sendable {
    case allow, block, limit
    var title: String {
        switch self {
        case .allow: String(localized: "network.mode.allow")
        case .block: String(localized: "network.mode.block")
        case .limit: String(localized: "network.mode.limit")
        }
    }
}

enum NetworkRuleScope: String, Codable, CaseIterable, Sendable {
    case background, always
    var title: String { self == .background ? String(localized: "network.scope.background") : String(localized: "network.scope.always") }
}

struct NetworkRule: Codable, Equatable, Sendable {
    var mode: NetworkRuleMode = .allow
    var scope: NetworkRuleScope = .background
    var delaySeconds: Double = 3
    var downloadKiBPerSecond: Int = 1024
    var uploadKiBPerSecond: Int = 256
    var isActive: Bool { mode != .allow }

    func validated() -> NetworkRule {
        NetworkRule(mode: mode, scope: scope,
                    delaySeconds: delaySeconds.isFinite ? min(300, max(0, delaySeconds)) : 3,
                    downloadKiBPerSecond: min(102400, max(16, downloadKiBPerSecond)),
                    uploadKiBPerSecond: min(102400, max(16, uploadKiBPerSecond)))
    }
}

/// 配置、权限和执行状态分开表达。缺少系统扩展时，规则始终标为待启用。
enum NetworkRuleStatus: Equatable, Sendable {
    case original, paused, waiting, foreground, pendingExtension, blocked, limited

    var title: String {
        switch self {
        case .original: String(localized: "network.status.original")
        case .paused: String(localized: "network.status.paused")
        case .waiting: String(localized: "network.status.waiting")
        case .foreground: String(localized: "network.status.foreground")
        case .pendingExtension: String(localized: "network.status.pending")
        case .blocked: String(localized: "network.status.blocked")
        case .limited: String(localized: "network.status.limited")
        }
    }
}

/// 纯策略供界面与后续系统扩展共享；能力未就绪时不产生控制动作。
enum NetworkPolicy {
    static func status(rule: NetworkRule, enabled: Bool, controlAvailable: Bool,
                       foreground: Bool, backgroundSeconds: Double) -> NetworkRuleStatus {
        guard rule.isActive else { return .original }
        guard controlAvailable else { return .pendingExtension }
        guard enabled else { return .paused }
        if rule.scope == .background {
            guard !foreground else { return .foreground }
            guard backgroundSeconds >= rule.delaySeconds else { return .waiting }
        }
        return rule.mode == .block ? .blocked : .limited
    }
}

/// 每个应用、每个传输方向独立持有额度。计划更改时应重建，防止继承旧额度。
struct NetworkTokenBucket {
    private var available: Double = 0
    private var lastTime: TimeInterval?
    let bytesPerSecond: Double
    let burstBytes: Double

    init(kibPerSecond: Int) {
        bytesPerSecond = Double(min(102400, max(16, kibPerSecond))) * 1024
        burstBytes = max(16384, bytesPerSecond * 0.2)
    }

    mutating func reserve(bytes: Int, at time: TimeInterval) -> TimeInterval {
        guard bytes > 0, time.isFinite else { return 0 }
        if let lastTime {
            available = min(burstBytes, available + max(0, time - lastTime) * bytesPerSecond)
        } else { available = burstBytes }
        lastTime = time
        available -= Double(bytes)
        return max(0, -available / bytesPerSecond)
    }
}
