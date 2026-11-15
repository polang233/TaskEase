import Foundation

/// 规则的一行摘要，列表与详情共用：时机 · 性能 · 音量 · 优先级。只读规则，不参与保存与执行。
extension AppRule {
    func summary(includesTiming: Bool = true) -> String {
        var parts: [String] = []
        if includesTiming { parts.append(timingTitle) }
        if limitsPerformance {
            parts.append(suspends ? String(localized: "mode.suspend") : "CPU \(Int(cpuPercent))%")
        }
        if adjustsVolume {
            parts.append(volumePercent == 0 ? String(localized: "rule.volume.mute")
                                            : String(localized: "rule.volume") + " \(Int(volumePercent))%")
        }
        if lowersPriority && !suspends { parts.append(String(localized: "mode.gentle")) }
        return parts.joined(separator: " · ")
    }

    /// 旧规则的等待时间可能不在预设中，取最接近的档位。
    var delayIndex: Int {
        if alwaysLimit { return 0 }
        let presets = Self.delayPresets
        return (1..<presets.count).min { abs(presets[$0] - delaySeconds) < abs(presets[$1] - delaySeconds) } ?? 2
    }

    var timingTitle: String {
        if alwaysLimit { return String(localized: "rule.timing.always") }
        let seconds = Int(Self.delayPresets[delayIndex])
        return seconds >= 60 ? String(localized: "rule.timing.minutes \(seconds / 60)")
                             : String(localized: "rule.timing.seconds \(seconds)")
    }

    /// 滑杆刻度的短文字。
    static func shortDelayTitle(index: Int) -> String {
        guard index > 0 else { return String(localized: "rule.timing.mark.always") }
        let seconds = Int(delayPresets[index])
        return seconds >= 60 ? String(localized: "rule.timing.short.minutes \(seconds / 60)")
                             : String(localized: "rule.timing.short.seconds \(seconds)")
    }
}
