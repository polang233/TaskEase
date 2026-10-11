import SwiftUI
import AppKit

/// 数字在浅色外观使用更深的色值，保持绿色到红色的提示同时保证可读性。
private enum MetricPalette {
    static let green = adaptive(light: 0x267B36, dark: 0x30D158)
    static let yellow = adaptive(light: 0x8A6500, dark: 0xFFD60A)
    static let orange = adaptive(light: 0xAD5700, dark: 0xFF9F0A)
    static let red = adaptive(light: 0xBA2525, dark: 0xFF453A)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        })
    }
}

extension MetricSeverity {
    var color: Color {
        switch self {
        case .unknown: .secondary
        case .normal: MetricPalette.green
        case .elevated: MetricPalette.yellow
        case .high: MetricPalette.orange
        case .critical: MetricPalette.red
        }
    }
}

/// 根据可用宽度切换一行或两行概览，静态颜色提示不会产生动画或额外采样。
struct SystemStrip: View {
    let reading: SystemReading
    var isPaused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 22) {
                    cpu; gpu; memory; network
                    Spacer(minLength: 8)
                    temperature
                }.fixedSize(horizontal: true, vertical: false)
                VStack(spacing: 12) {
                    HStack { cpu; Spacer(minLength: 12); gpu; Spacer(minLength: 12); temperature }
                    HStack(alignment: .top) { memory; Spacer(minLength: 16); network }
                }
            }
            if isPaused {
                Label("已暂停刷新", systemImage: "snowflake")
                    .font(.caption).foregroundStyle(.blue)
                    .help("当前显示上次采样的数据。切回前台后更新，后台规则继续执行。")
                    .accessibilityIdentifier("display-paused")
            }
        }.font(.callout).monospacedDigit()
            .padding(.horizontal, 20).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isPaused ? Color.blue.opacity(0.04) : Color.clear)
    }

    private var cpu: some View {
        Label {
            HStack(spacing: 5) {
                Text("CPU")
                Text(Display.percent(reading.cpuPercent)).foregroundStyle(MetricSeverity.utilization(reading.cpuPercent).color)
            }
        } icon: { Image(systemName: "cpu").foregroundStyle(.secondary) }
            .fixedSize().help("整机全部 CPU 核心的总体占用，满载为 100%。应用列表另按单核时间计算。")
    }

    private var gpu: some View {
        Label {
            HStack(spacing: 5) {
                Text("GPU")
                Text(Display.percent(reading.gpuPercent)).foregroundStyle(MetricSeverity.utilization(reading.gpuPercent).color)
            }
        } icon: { Image(systemName: "square.3.layers.3d").foregroundStyle(.secondary) }
            .fixedSize().help("整机 GPU 驱动利用率估计值；缺失时显示 —。")
    }

    private var memory: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label {
                Text("内存 \(Display.gigabytes(reading.memory?.usedBytes)) / \(Display.gigabytes(reading.memory?.totalBytes)) GB")
                    .foregroundStyle(MetricSeverity.utilization(reading.memory?.percent).color)
            } icon: { Image(systemName: "memorychip").foregroundStyle(.secondary) }
            Text("压缩 \(Display.gigabytes(reading.memory?.compressedBytes)) GB")
                .font(.caption).foregroundStyle(.secondary)
        }.fixedSize().help("整机物理内存占用与总容量。压缩内存表示压缩器实际占用，已包含在已用内存内。颜色表示占用比例，不等同于系统内存压力。")
    }

    private var network: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("↓ \(Display.megabytesPerSecond(reading.network?.receiveRate)) MB/s")
            Text("↑ \(Display.megabytesPerSecond(reading.network?.sendRate)) MB/s")
                .font(.caption).foregroundStyle(.secondary)
        }.fixedSize().help("整机活动 Wi-Fi 和以太网接口的下载、上传流量。MB/s 为每秒百万字节；不重复累加 VPN 和回环虚拟接口。首次采样需等待速度基线。")
            .accessibilityElement(children: .combine).accessibilityLabel("全局网速")
    }

    private var temperature: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Label(reading.temperatureCelsius == nil ? reading.thermalLabel : Display.temperature(reading.temperatureCelsius),
                  systemImage: "thermometer.medium")
                .foregroundStyle(thermalColor)
            if reading.temperatureCelsius != nil {
                Text("芯片最高 · \(reading.thermalLabel)").font(.caption).foregroundStyle(.secondary)
            }
        }.fixedSize().help("可读芯片传感器的最高摄氏度，最快每 4 秒读取一次。显示到 0.1°C，不代表测量误差为 0.1°C；读取失败时显示系统热状态。")
    }

    private var thermalColor: Color {
        let system: MetricSeverity = switch reading.thermalLabel {
        case "严重": .critical
        case "较高": .high
        case "轻度升温": .elevated
        case "正常": .normal
        default: .unknown
        }
        let sensor = MetricSeverity.temperature(reading.temperatureCelsius)
        return (system.rawValue > sensor.rawValue ? system : sensor).color
    }
}

#Preview("概览") {
    SystemStrip(reading: SystemReading(cpuPercent: 18, gpuPercent: 24, thermalLabel: "正常",
        memory: .init(usedBytes: 14 * 1_073_741_824, totalBytes: 24 * 1_073_741_824, compressedBytes: 1_073_741_824),
        network: .init(receiveRate: 12_345_678, sendRate: 123_456), temperatureCelsius: 54.3))
        .frame(width: 420)
}
