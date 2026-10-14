import SwiftUI

/// 原始值只作为界面标识，显示名称通过本地化获取。
enum SystemMetric: String {
    case cpu, gpu, memory, temperature, network

    var title: String {
        switch self {
        case .cpu: String(localized: "metric.cpu")
        case .gpu: String(localized: "metric.gpu")
        case .memory: String(localized: "metric.memory")
        case .temperature: String(localized: "metric.temperature")
        case .network: String(localized: "metric.network")
        }
    }

    /// 概览数值槽的宽度模板：取可能出现的最长文本，包括各语言的热状态名称。
    var widestValues: [String] {
        switch self {
        case .temperature: ["100.0°C"] + ThermalLevel.allCases.map(\.title)
        default: ["100.0%"]
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "square.3.layers.3d"
        case .memory: "memorychip"
        case .temperature: "thermometer.medium"
        case .network: "network"
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
                Text(metric.title).font(.headline)
                Spacer()
                Text(primaryValue).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(primaryColor)
            }
            switch metric {
            case .cpu:
                if let model = hardware.cpuModel { row(Text("detail.model"), model) }
                row(Text("detail.cores"), String(localized: "detail.coreCount \(hardware.physicalCores)"))
                ForEach(hardware.clusters, id: \.self) {
                    row(Text($0.name), String(localized: "detail.coreCount \($0.cores)"))
                }
            case .gpu:
                if let model = hardware.gpuModel { row(Text("detail.model"), model) }
                if let cores = hardware.gpuCores { row(Text("detail.cores"), String(localized: "detail.coreCount \(cores)")) }
                row(Text("detail.vram"), String(localized: "detail.sharedMemory \(Display.gigabytes(hardware.memoryBytes))"))
                gpuSources
            case .memory:
                row(Text("detail.used"), "\(Display.gigabytes(reading.memory?.usedBytes)) / \(Display.gigabytes(reading.memory?.totalBytes)) GB")
                row(Text("detail.compressed"), "\(Display.gigabytes(reading.memory?.compressedBytes)) GB")
                row(Text("detail.swap"), "\(Display.gigabytes(reading.memory?.swapBytes)) GB")
            case .temperature:
                row(Text("detail.thermal"), reading.thermal.title)
                note("detail.sensorNote")
            case .network:
                row(Text("detail.upload"), Display.networkRate(reading.network?.sendRate))
                row(Text("detail.download"), Display.networkRate(reading.network?.receiveRate))
                note("strip.network.help")
            }
            if isPaused { note("detail.paused") }
        }.font(.caption).padding(12).frame(width: 240)
    }

    /// 占用来源：各进程 GPU 执行时间占比，整机利用率高出合计较多时补一行未归属的差额。
    @ViewBuilder private var gpuSources: some View {
        let sources = reading.gpuSources
        if !sources.isEmpty {
            Divider().padding(.vertical, 2)
            Text("detail.gpuSources").foregroundStyle(.secondary)
            ForEach(sources, id: \.name) { source in
                row(Text(verbatim: source.name), Display.percent(source.percent))
                if source.compositing > 0 {
                    Text("detail.gpuCompositing \(Display.percent(source.compositing))")
                        .foregroundStyle(.tertiary).padding(.leading, 10)
                }
            }
            if let total = reading.gpuPercent {
                let gap = total - sources.reduce(0) { $0 + $1.percent }
                if gap >= 5 { row(Text("detail.gpuUnattributed"), Display.percent(gap)) }
            }
            if sources.contains(where: { $0.compositing > 0 }) {
                note("detail.compositingNote")
            } else if let top = sources.first, top.isWindowServer, top.percent >= 10 {
                note("detail.windowServerNote")
            }
        }
    }

    private var primaryValue: String {
        switch metric {
        case .cpu: Display.percent(reading.cpuPercent)
        case .gpu: Display.percent(reading.gpuPercent)
        case .memory: Display.percent(reading.memory?.percent)
        case .temperature: Display.temperature(reading.temperatureCelsius)
        case .network: Display.networkRate(reading.network.map { ($0.sendRate ?? 0) + ($0.receiveRate ?? 0) })
        }
    }

    private var primaryColor: Color {
        switch metric {
        case .cpu: MetricPalette.percent(reading.cpuPercent)
        case .gpu: MetricPalette.percent(reading.gpuPercent)
        case .memory: MetricPalette.percent(reading.memory?.percent)
        case .temperature: MetricPalette.thermal(celsius: reading.temperatureCelsius, level: reading.thermal)
        case .network: .primary
        }
    }

    private func row(_ title: Text, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            title.foregroundStyle(.secondary)
            Spacer(minLength: 14)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
    }
}
