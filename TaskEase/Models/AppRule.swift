import Foundation

// 原始值用于 rules.v1 存储，界面名称调整时保持序列化格式稳定。
// 新规则只用 budget 与 suspend 表示性能限制；gentle 与 off 仅用于读取旧规则和写入降级兼容字段。
enum ControlMode: String, Codable, CaseIterable, Hashable, Sendable {
    case off, gentle, budget, suspend

    var title: String {
        switch self {
        case .off: String(localized: "mode.off")
        case .gentle: String(localized: "mode.gentle")
        case .budget: String(localized: "mode.budget")
        case .suspend: String(localized: "mode.suspend")
        }
    }

    /// 性能限制中可选的方式；界面上 CPU 上限滑杆拖到最左即为暂停。
    static let limits: [ControlMode] = [.budget, .suspend]
}

/// 一个应用的后台规则：总开关、生效等待时间，以及可组合的性能限制、后台音量和降低优先级。
/// `alwaysLimit` 表示前台也限制，此时不使用等待时间；各项限制按同一时机生效。
struct AppRule: Equatable, Sendable {
    var isEnabled = false
    var delaySeconds: Double = 3
    var alwaysLimit = false
    var limitsPerformance = true
    var performance: ControlMode = .budget
    var cpuPercent: Double = 20
    var adjustsVolume = false
    /// 后台音量百分比，0 为静音。
    var volumePercent: Double = 0
    var lowersPriority = false

    /// 至少有一项限制时才需要监控和执行。
    var isActive: Bool { isEnabled && (limitsPerformance || adjustsVolume || lowersPriority) }
    /// 交给工作进程执行的部分：性能限制或降低优先级。
    var needsWorker: Bool { isEnabled && (limitsPerformance || lowersPriority) }
    var suspends: Bool { limitsPerformance && performance == .suspend }

    /// 界面滑块的预设档位，单位为秒；0 对应始终限制。
    static let delayPresets: [Double] = [0, 1, 3, 5, 10, 30, 60, 120, 300]

    /// 将磁盘或界面输入规范到有效范围，处理非有限数值。
    func validated() -> AppRule {
        var rule = self
        if !ControlMode.limits.contains(rule.performance) { rule.performance = .budget }
        // 暂停应用在前台会让应用无法使用，因此不允许始终生效。
        rule.alwaysLimit = alwaysLimit && !rule.suspends
        rule.cpuPercent = cpuPercent.isFinite ? min(200, max(5, cpuPercent)) : 20
        rule.volumePercent = volumePercent.isFinite ? min(90, max(0, volumePercent)) : 0
        rule.delaySeconds = rule.alwaysLimit ? 0 : delaySeconds.isFinite ? min(300, max(0, delaySeconds)) : 3
        return rule
    }
}

extension AppRule {
    /// 按旧版单一模式构造规则，用于迁移旧数据、预览与测试。
    init(mode: ControlMode, cpuPercent: Double = 20, delaySeconds: Double = 3, alwaysLimit: Bool = false) {
        self.init(isEnabled: mode != .off, delaySeconds: delaySeconds, alwaysLimit: alwaysLimit,
                  limitsPerformance: mode != .gentle, performance: mode == .suspend ? .suspend : .budget,
                  cpuPercent: cpuPercent, lowersPriority: mode == .gentle)
    }
}

extension AppRule: Codable {
    private enum CodingKeys: String, CodingKey {
        case mode, cpuPercent, delaySeconds, alwaysLimit
        case enabled, limitsPerformance, performance, adjustsVolume, volumePercent, lowersPriority
    }

    /// 缺少新字段的旧规则按原模式迁移：降低优先级对应只降优先级，其余对应性能限制。
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try values.decode(ControlMode.self, forKey: .mode)
        cpuPercent = try values.decode(Double.self, forKey: .cpuPercent)
        delaySeconds = try values.decode(Double.self, forKey: .delaySeconds)
        alwaysLimit = try values.decodeIfPresent(Bool.self, forKey: .alwaysLimit) ?? false
        if let enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) {
            isEnabled = enabled
            limitsPerformance = try values.decodeIfPresent(Bool.self, forKey: .limitsPerformance) ?? true
            performance = try values.decodeIfPresent(ControlMode.self, forKey: .performance) ?? .budget
            adjustsVolume = try values.decodeIfPresent(Bool.self, forKey: .adjustsVolume) ?? false
            volumePercent = try values.decodeIfPresent(Double.self, forKey: .volumePercent) ?? 0
            lowersPriority = try values.decodeIfPresent(Bool.self, forKey: .lowersPriority) ?? false
        } else {
            self = AppRule(mode: legacy, cpuPercent: cpuPercent, delaySeconds: delaySeconds, alwaysLimit: alwaysLimit)
        }
    }

    /// 同时写入旧版 `mode` 字段，降级到旧版本时规则仍可读取。
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        let legacy: ControlMode = !isActive ? .off : limitsPerformance ? performance : lowersPriority ? .gentle : .off
        try values.encode(legacy, forKey: .mode)
        try values.encode(cpuPercent, forKey: .cpuPercent)
        try values.encode(delaySeconds, forKey: .delaySeconds)
        try values.encode(alwaysLimit, forKey: .alwaysLimit)
        try values.encode(isEnabled, forKey: .enabled)
        try values.encode(limitsPerformance, forKey: .limitsPerformance)
        try values.encode(performance, forKey: .performance)
        try values.encode(adjustsVolume, forKey: .adjustsVolume)
        try values.encode(volumePercent, forKey: .volumePercent)
        try values.encode(lowersPriority, forKey: .lowersPriority)
    }
}

enum RuleStatus: Equatable, Sendable {
    case unmanaged, foreground, waiting, gentle, budget, suspended, muted, quieted, paused, unavailable, notRunning

    var title: String {
        switch self {
        case .unmanaged: String(localized: "status.unmanaged")
        case .foreground: String(localized: "status.foreground")
        case .waiting: String(localized: "status.waiting")
        case .gentle: String(localized: "status.gentle")
        case .budget: String(localized: "status.budget")
        case .suspended: String(localized: "status.suspended")
        case .muted: String(localized: "status.muted")
        case .quieted: String(localized: "status.quieted")
        case .paused: String(localized: "status.paused")
        case .unavailable: String(localized: "status.readOnly")
        case .notRunning: String(localized: "status.notRunning")
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
