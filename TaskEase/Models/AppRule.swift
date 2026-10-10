import Foundation

// Raw values are part of rules.v1 and stay stable when display names change.
enum ControlMode: String, Codable, CaseIterable, Hashable, Sendable {
    case off, gentle, budget

    var title: String {
        switch self {
        case .off: "保持原样"
        case .gentle: "降低后台优先级"
        case .budget: "限制 CPU 使用"
        }
    }
}

struct AppRule: Codable, Equatable, Sendable {
    var mode: ControlMode = .off
    var cpuPercent: Double = 20
    var delaySeconds: Double = 3
    var isActive: Bool { mode != .off }

    func validated() -> AppRule {
        AppRule(mode: mode,
                cpuPercent: cpuPercent.isFinite ? min(200, max(5, cpuPercent)) : 20,
                delaySeconds: delaySeconds.isFinite ? min(300, max(0, delaySeconds)) : 3)
    }
}

enum RuleStatus: Equatable, Sendable {
    case unmanaged, foreground, waiting, gentle, budget, paused, unavailable, notRunning

    var title: String {
        switch self {
        case .unmanaged: "保持原样"
        case .foreground: "前台正常"
        case .waiting: "等待生效"
        case .gentle: "已降低优先级"
        case .budget: "CPU 限制生效"
        case .paused: "规则已暂停"
        case .unavailable: "只读"
        case .notRunning: "未运行"
        }
    }
}

/// One shared allowance covers every owned process of an application.
/// Negative credit pauses the group; idle credit is capped to prevent an unlimited burst.
struct BudgetCredit: Sendable {
    private(set) var credit: Double = 0

    mutating func update(elapsedTicks: UInt64, usedTicks: UInt64,
                         fraction: Double, burstTicks: Double) -> Bool {
        credit = min(burstTicks, credit + Double(elapsedTicks) * fraction - Double(usedTicks))
        return credit < 0
    }
}
