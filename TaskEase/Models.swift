import Foundation

struct ProcessIdentity: Hashable, Codable, Sendable {
    let pid: Int32
    let uid: UInt32
    let startSeconds: UInt64
    let startMicroseconds: UInt64
}

struct ProcessSample: Sendable {
    let identity: ProcessIdentity
    let parentPID: Int32
    let status: UInt32
    let cpuTicks: UInt64
    let memoryBytes: UInt64
    let readBytes: UInt64
    let writeBytes: UInt64
    let wakeups: UInt64
}

enum ControlMode: String, Codable, CaseIterable, Hashable, Sendable {
    case off, gentle, budget
    var title: String {
        switch self {
        case .off: return "不管理"
        case .gentle: return "温和后台调度"
        case .budget: return "CPU 预算"
        }
    }
}

struct AppRule: Codable, Equatable, Sendable {
    var mode: ControlMode = .off
    var cpuPercent: Double = 20
    var delaySeconds: Double = 3
    func validated() -> AppRule {
        AppRule(mode: mode,
                cpuPercent: cpuPercent.isFinite ? min(200, max(5, cpuPercent)) : 20,
                delaySeconds: delaySeconds.isFinite ? min(30, max(0, delaySeconds)) : 3)
    }
}

enum RuleStatus: Equatable, Sendable {
    case unmanaged, foreground, waiting, gentle, budget, paused, unavailable
    var title: String {
        switch self {
        case .unmanaged: return "未管理"
        case .foreground: return "前台正常"
        case .waiting: return "等待后台"
        case .gentle: return "后台温和调度"
        case .budget: return "CPU 预算生效"
        case .paused: return "自动管理已暂停"
        case .unavailable: return "只读"
        }
    }
}

struct ControlTarget: Hashable, Codable, Sendable {
    let identity: ProcessIdentity
    let executablePath: String
    let bundlePath: String
}

struct ControlGroup: Codable, Sendable {
    let bundleID: String
    let mode: ControlMode
    let cpuPercent: Double
    let targets: [ControlTarget]
}

struct ControlMessage: Codable, Sendable {
    let groups: [ControlGroup]
    var shutdown: Bool = false
}

struct WorkerEvent: Codable, Sendable {
    let kind: String
    let message: String
    var processCount: Int = 0
}

struct RecoveryRecord: Codable, Sendable {
    let worker: ProcessIdentity
    let controller: ProcessIdentity
    var background: [ControlTarget] = []
    var suspension: [ControlTarget] = []
}

struct SystemReading: Sendable {
    var cpuPercent: Double?
    var gpuPercent: Double?
    var thermalLabel: String = "正常"
}

struct AppReading: Identifiable {
    let id: String
    let name: String
    let bundlePaths: [String]
    let primaryPIDs: Set<Int32>
    var targets: [ControlTarget]
    var samples: [ProcessSample]
    var cpuPercent: Double?
    var memoryBytes: UInt64
    var readRate: Double
    var writeRate: Double
    var canControl: Bool
    var isHidden: Bool
    var status: RuleStatus = .unmanaged
}

struct BudgetCredit: Sendable {
    private(set) var credit: Double = 0
    mutating func update(elapsedTicks: UInt64, usedTicks: UInt64, fraction: Double, burstTicks: Double) -> Bool {
        credit = min(burstTicks, credit + Double(elapsedTicks) * fraction - Double(usedTicks))
        return credit < 0
    }
}
