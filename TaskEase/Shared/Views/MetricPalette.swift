import SwiftUI
import AppKit

/// 占比从绿到红分十档。浅色外观每档对白色背景的对比度不低于 4:1，深色外观不低于 5:1。
enum MetricPalette {
    private static let light: [UInt32] = [0x0C9217, 0x20920C, 0x3E900C, 0x598B0B, 0x73860B,
                                          0x897F0B, 0xA5770D, 0xC66410, 0xE74413, 0xEF3434]
    private static let dark: [UInt32] = [0x0BDA1D, 0x2ADA0B, 0x5ADA0B, 0x8ADA0B, 0xBADA0B,
                                         0xDACB0B, 0xDA9B0B, 0xDF6D0C, 0xF45A2C, 0xF65555]
    private static let steps: [Color] = zip(light, dark).map(adaptive)

    /// `fraction` 为 0...1 的占比；无法读取时使用次要文字颜色。
    static func color(_ fraction: Double?) -> Color {
        guard let fraction, fraction.isFinite else { return .secondary }
        let index = Int((min(1, max(0, fraction)) * Double(steps.count)).rounded(.down))
        return steps[min(steps.count - 1, index)]
    }

    /// 从绿色到当前占比所在档位的颜色序列，用于渐变占用条。
    static func gradient(upTo fraction: Double) -> [Color] {
        let index = min(steps.count - 1, Int((min(1, max(0, fraction)) * Double(steps.count)).rounded(.down)))
        return index == 0 ? [steps[0], steps[0]] : Array(steps[0...index])
    }

    static func percent(_ value: Double?) -> Color { color(value.map { $0 / 100 }) }

    /// 应用 CPU 为单核口径，按全部核心能力归一后取色。
    static func applicationCPU(_ value: Double?, cores: Int = ProcessInfo.processInfo.activeProcessorCount) -> Color {
        color(value.map { $0 / 100 / Double(max(1, cores)) })
    }

    /// 温度按 35–95°C 映射；系统热状态更高时取较高档，避免传感器缺失时误显示为绿色。
    static func thermal(celsius: Double?, label: String) -> Color {
        let state: Double? = switch label {
        case "严重": 1
        case "较高": 0.75
        case "轻度升温": 0.45
        case "正常": 0
        default: nil
        }
        let sensor = celsius.map { ($0 - 35) / 60 }
        guard state != nil || sensor != nil else { return .secondary }
        return color(max(state ?? 0, sensor ?? 0))
    }

    static func thermalFraction(celsius: Double?) -> Double? {
        celsius.map { min(1, max(0, ($0 - 35) / 60)) }
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        })
    }
}
