import Foundation

/// 菜单栏、URL Scheme 与快捷指令发起的临时操作。只保存在内存中：退出、睡眠或应用退出后即失效，
/// 暂停由工作进程执行并写入恢复记录，主应用崩溃或失联时同样由恢复机制解除。
enum TemporaryAction: Equatable, Sendable {
    /// 在后台时暂停应用，直到期限；切回前台照常使用。
    case pause(until: Date)
    /// 规则暂时不执行，直到期限或下次切回该应用。
    case release(until: Date)

    var until: Date {
        switch self {
        case .pause(let until), .release(let until): until
        }
    }

    var isPause: Bool { if case .pause = self { true } else { false } }

    /// 临时暂停时长范围，单位为分钟。
    static let minutesRange: ClosedRange<Double> = 1...240
    static let defaultMinutes: Double = 60
    /// “立即恢复”让规则暂停执行的时长。
    static let releaseMinutes: Double = 60

    static func clampedMinutes(_ minutes: Double) -> Double {
        minutes.isFinite ? min(minutesRange.upperBound, max(minutesRange.lowerBound, minutes.rounded())) : defaultMinutes
    }
}
