import SwiftUI
import Charts

/// 详情里随排序依据切换的近期折线图：CPU、内存、GPU 为单条曲线，磁盘与网络为读写（收发）两条。
struct UsageChart: View {
    let key: AppSortKey
    let points: [UsagePoint]
    let scale: CPUScale

    /// 显示最近三分钟的记录；横轴是累计记录时间，暂停采样的空档不占位置。
    private static let span: TimeInterval = 180

    private struct Sample: Identifiable {
        let id: Int
        let time: TimeInterval
        let value: Double
        let name: String
    }

    private var lines: [(name: String, color: Color, pick: (UsagePoint) -> Double?)] {
        switch key {
        case .cpu, .name:
            [("CPU", .accentColor, { point in
                scale == .machine ? point.cpu.map { $0 / Double(max(1, ProcessInfo.processInfo.activeProcessorCount)) } : point.cpu })]
        case .memory: [(String(localized: "metric.memory"), .accentColor, { $0.memory })]
        case .gpu: [("GPU", .accentColor, { $0.gpu })]
        case .disk: [(String(localized: "rule.disk.read"), .blue, { $0.read }),
                     (String(localized: "rule.disk.write"), .orange, { $0.write })]
        case .network: [(String(localized: "rule.network.receive"), .blue, { $0.receive }),
                        (String(localized: "rule.network.send"), .orange, { $0.send })]
        }
    }

    private var samples: [Sample] {
        guard let end = points.last?.time else { return [] }
        let recent = points.filter { $0.time >= end - Self.span }
        var result: [Sample] = []
        for line in lines {
            for point in recent {
                guard let value = line.pick(point) else { continue }
                result.append(Sample(id: result.count, time: point.time, value: value, name: line.name))
            }
        }
        return result
    }

    /// 纵轴上限取 1、2、5 的整数倍，并保留最小量程，避免几乎为零的数值被放大成满格。
    /// 字节类指标与界面其余部分一致，按 1024 进制取整，刻度才会显示成 512 KB、2 MB 这样的整数。
    private func ceiling(_ peak: Double) -> Double {
        let isBytes = key != .cpu && key != .name && key != .gpu
        let floor: Double
        switch key {
        case .cpu, .name, .gpu: floor = 10
        case .memory: floor = 128 * 1_048_576
        case .disk: floor = 256 * 1024
        case .network: floor = 128 * 1024
        }
        let target = max(floor, peak * 1.15)
        let base = isBytes ? 1024.0 : 10.0
        let unit = pow(base, (log(target) / log(base)).rounded(.down))
        let steps: [Double] = isBytes ? [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000] : [1, 2, 5, 10]
        for step in steps where step * unit >= target { return step * unit }
        return target
    }

    private func label(_ value: Double) -> String {
        switch key {
        case .cpu, .name, .gpu: "\(Int(value.rounded()))%"
        case .memory: Display.bytes(UInt64(max(0, value)))
        case .disk: Display.rate(value)
        case .network: Display.networkRate(value)
        }
    }

    var body: some View {
        let data = samples
        let top = ceiling(data.map(\.value).max() ?? 0)
        let end = points.last?.time ?? 0
        Chart(data) { sample in
            if lines.count == 1 {
                AreaMark(x: .value("t", sample.time), y: .value("v", sample.value), series: .value("s", sample.name))
                    .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
            }
            LineMark(x: .value("t", sample.time), y: .value("v", sample.value), series: .value("s", sample.name))
                .foregroundStyle(by: .value("n", sample.name))
                .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
        }
        .chartForegroundStyleScale(domain: lines.map(\.name), range: lines.map(\.color))
        .chartLegend(lines.count > 1 ? .visible : .hidden)
        .chartXScale(domain: (end - Self.span)...end)
        .chartYScale(domain: 0...top)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, top / 2, top]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel {
                    if let number = value.as(Double.self) { Text(label(number)).font(.caption2).monospacedDigit() }
                }.foregroundStyle(.secondary)
            }
        }
        .frame(height: 120)
        .accessibilityLabel(Text("usage.chart.accessibility \(key.title)"))
    }
}
