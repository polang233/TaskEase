import Foundation

// 原始值用于 rules.v1 存储，界面名称调整时保持序列化格式稳定。
enum ControlMode: String, Codable, CaseIterable, Hashable, Sendable {
    case off, gentle, budget, suspend

    var title: String {
        switch self {
        case .off: "保持原样"
        case .gentle: "降低优先级"
        case .budget: "限制 CPU"
        case .suspend: "暂停应用"
        }
    }

    /// 规则编辑器中可选的限制方式。
    static let limits: [ControlMode] = [.budget, .gentle, .suspend]
}

/// 一个应用的后台限制模式、CPU 上限和生效等待时间。
/// `alwaysLimit` 表示前台也限制，此时不使用等待时间；旧规则缺少该字段时按后台限制读取。
struct AppRule: Codable, Equatable, Sendable {
    var mode: ControlMode = .off
    var cpuPercent: Double = 20
    var delaySeconds: Double = 3
    var alwaysLimit = false
    var isActive: Bool { mode != .off }

    /// 界面滑块的预设档位，单位为秒；0 对应始终限制。
    static let delayPresets: [Double] = [0, 1, 3, 5, 10, 30, 60, 120, 300]

    /// 将磁盘或界面输入规范到有效范围，处理非有限数值。
    func validated() -> AppRule {
        // 暂停应用在前台会让应用无法使用，因此不允许始终生效。
        let always = alwaysLimit && mode != .suspend
        return AppRule(mode: mode,
                cpuPercent: cpuPercent.isFinite ? min(200, max(5, cpuPercent)) : 20,
                delaySeconds: always ? 0 : delaySeconds.isFinite ? min(300, max(0, delaySeconds)) : 3,
                alwaysLimit: always)
    }
}

extension AppRule {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = try values.decode(ControlMode.self, forKey: .mode)
        cpuPercent = try values.decode(Double.self, forKey: .cpuPercent)
        delaySeconds = try values.decode(Double.self, forKey: .delaySeconds)
        alwaysLimit = try values.decodeIfPresent(Bool.self, forKey: .alwaysLimit) ?? false
    }
}

enum RuleStatus: Equatable, Sendable {
    case unmanaged, foreground, waiting, gentle, budget, suspended, paused, unavailable, notRunning

    var title: String {
        switch self {
        case .unmanaged: "保持原样"
        case .foreground: "前台正常"
        case .waiting: "等待生效"
        case .gentle: "已降低优先级"
        case .budget: "CPU 限制中"
        case .suspended: "已暂停运行"
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
