import Foundation

// 原始值用于 rules.v1 存储，界面名称调整时保持序列化格式稳定。
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

/// 一个应用的后台限制模式、CPU 上限和生效等待时间。
struct AppRule: Codable, Equatable, Sendable {
    var mode: ControlMode = .off
    var cpuPercent: Double = 20
    var delaySeconds: Double = 3
    var isActive: Bool { mode != .off }

    /// 将磁盘或界面输入规范到有效范围，处理非有限数值。
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

/// 应用自有进程共享 CPU 额度；负额度触发暂停，空闲额度有上限。
struct BudgetCredit: Sendable {
    private(set) var credit: Double = 0

    mutating func update(elapsedTicks: UInt64, usedTicks: UInt64,
                         fraction: Double, burstTicks: Double) -> Bool {
        credit = min(burstTicks, credit + Double(elapsedTicks) * fraction - Double(usedTicks))
        return credit < 0
    }
}
