import SwiftUI

enum SystemMetric: String {
    case cpu = "CPU", gpu = "GPU", memory = "内存", temperature = "温度"

    var shortTitle: String { rawValue }

    /// 概览数值槽的宽度模板：取可能出现的最长文本。
    var widestValues: [String] {
        switch self {
        case .temperature: ["100.0°C", "轻度升温"]
        default: ["100.0%"]
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "square.3.layers.3d"
        case .memory: "memorychip"
        case .temperature: "thermometer.medium"
        }
    }
}

/// 指标卡片使用已有快照；芯片型号与核心数来自首次读取后缓存的静态信息。
struct MetricDetails: View {
    let metric: SystemMetric
    let reading: SystemReading
    var isPaused = false
    private var hardware: HardwareProfile { .current }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.rawValue).font(.headline)
                Spacer()
                Text(primaryValue).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(primaryColor)
            }
            switch metric {
            case .cpu:
                if let model = hardware.cpuModel { row("型号", model) }
                row("核心", "\(hardware.physicalCores) 核")
                ForEach(hardware.clusters, id: \.self) { row($0.name, "\($0.cores) 核") }
            case .gpu:
                if let model = hardware.gpuModel { row("型号", model) }
                if let cores = hardware.gpuCores { row("核心", "\(cores) 核") }
                row("显存", "与 CPU 共用 \(Display.gigabytes(hardware.memoryBytes)) GB")
            case .memory:
                row("已用", "\(Display.gigabytes(reading.memory?.usedBytes)) / \(Display.gigabytes(reading.memory?.totalBytes)) GB")
                row("压缩", "\(Display.gigabytes(reading.memory?.compressedBytes)) GB")
                row("交换", "\(Display.gigabytes(reading.memory?.swapBytes)) GB")
            case .temperature:
                row("热状态", reading.thermalLabel)
                note("芯片传感器最高值，仅作参考")
            }
            if isPaused { note("刷新已暂停") }
        }.font(.caption).padding(12).frame(width: 220)
    }

    private var primaryValue: String {
        switch metric {
        case .cpu: Display.percent(reading.cpuPercent)
        case .gpu: Display.percent(reading.gpuPercent)
        case .memory: Display.percent(reading.memory?.percent)
        case .temperature: Display.temperature(reading.temperatureCelsius)
        }
    }

    private var primaryColor: Color {
        switch metric {
        case .cpu: MetricPalette.percent(reading.cpuPercent)
        case .gpu: MetricPalette.percent(reading.gpuPercent)
        case .memory: MetricPalette.percent(reading.memory?.percent)
        case .temperature: MetricPalette.thermal(celsius: reading.temperatureCelsius, label: reading.thermalLabel)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 14)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
    }
}
