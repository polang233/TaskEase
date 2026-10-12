import SwiftUI
import AppKit

/// 系统指标保持单行；指针移到 CPU、GPU、内存或温度上打开无箭头卡片，离开指标和卡片后立即关闭。
struct SystemStrip: View {
    let reading: SystemReading
    var isPaused = false
    var style: MetricDisplayStyle = .number
    @State private var active: SystemMetric?
    @State private var cards = HoverCardCoordinator()
    @State private var anchors: [SystemMetric: WeakAnchor] = [:]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(compact: false)
            row(compact: true)
        }.monospacedDigit().padding(.horizontal, 14).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isPaused ? Color.blue.opacity(0.04) : Color.clear)
            .onAppear { cards.onClose = { active = nil } }
            .onDisappear { cards.close() }
            .onExitCommand { cards.close() }
            .onChange(of: reading) { refreshCard() }
            .onChange(of: isPaused) { refreshCard() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in cards.close() }
    }

    private func row(compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 20) {
            metric(.cpu, compact: compact, value: Display.percent(reading.cpuPercent),
                   fraction: reading.cpuPercent.map { $0 / 100 })
            metric(.gpu, compact: compact, value: Display.percent(reading.gpuPercent),
                   fraction: reading.gpuPercent.map { $0 / 100 })
            metric(.memory, compact: compact, value: Display.percent(reading.memory?.percent),
                   fraction: reading.memory?.percent.map { $0 / 100 })
            metric(.temperature, compact: compact,
                   value: reading.temperatureCelsius == nil ? reading.thermalLabel : Display.temperature(reading.temperatureCelsius),
                   fraction: MetricPalette.thermalFraction(celsius: reading.temperatureCelsius),
                   color: MetricPalette.thermal(celsius: reading.temperatureCelsius, label: reading.thermalLabel))
            NetworkRateStack(reading: reading.network, compact: compact)
            if isPaused {
                Image(systemName: "snowflake").font(.caption).foregroundStyle(.blue)
                    .help("已暂停刷新，切回前台后更新")
                    .accessibilityLabel("已暂停刷新").accessibilityIdentifier("display-paused")
            }
        }.fixedSize(horizontal: true, vertical: false)
    }

    private func metric(_ kind: SystemMetric, compact: Bool, value: String, fraction: Double?, color: Color? = nil) -> some View {
        Button { active == kind && cards.isOpen ? cards.close() : open(kind) } label: {
            MetricGauge(kind: kind, value: value, fraction: fraction, color: color ?? MetricPalette.color(fraction),
                        style: style, compact: compact)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointingHand()
        .accessibilityLabel("\(kind.rawValue) \(value)")
        .accessibilityHint("显示详细信息")
        .accessibilityIdentifier("system-\(kind.rawValue)")
        .background(AnchorReader { view in
            if anchors[kind]?.view !== view { anchors[kind] = WeakAnchor(view) }
        })
        .onHover { inside in
            if inside { open(kind) }
            cards.anchorHover(inside)
        }
    }

    private func open(_ kind: SystemMetric) {
        guard active != kind || !cards.isOpen, let anchor = anchors[kind]?.view else { return }
        active = kind
        cards.show(anchor: anchor, content: details(kind))
    }

    private func refreshCard() {
        guard let active, cards.isOpen else { return }
        cards.update(content: details(active))
    }

    private func details(_ kind: SystemMetric) -> AnyView {
        AnyView(MetricDetails(metric: kind, reading: reading, isPaused: isPaused))
    }
}

/// 单个指标的三种外观：数字、圆环（中心为指标图标）、进度条。数值槽按最长内容预留宽度，避免数字变化时整行左右移动。
private struct MetricGauge: View {
    let kind: SystemMetric
    let value: String
    let fraction: Double?
    let color: Color
    let style: MetricDisplayStyle
    let compact: Bool

    var body: some View {
        HStack(spacing: 5) {
            switch style {
            case .number:
                Image(systemName: kind.symbol).foregroundStyle(.secondary)
                if !compact { Text(kind.shortTitle) }
            case .ring:
                ring
                if !compact { Text(kind.shortTitle) }
            case .bar:
                Text(kind.shortTitle).foregroundStyle(compact ? .secondary : .primary)
                bar
            }
            ZStack(alignment: .leading) {
                ForEach(kind.widestValues, id: \.self) { Text($0).hidden() }
                Text(value).foregroundStyle(color)
            }
        }.font(compact ? .caption : .callout).frame(height: 24).fixedSize()
    }

    private var ring: some View {
        let size: CGFloat = compact ? 18 : 21
        return ZStack {
            Circle().stroke(.quaternary, lineWidth: 2.5)
            Circle().trim(from: 0, to: min(1, max(0, fraction ?? 0)))
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: kind.symbol)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(.secondary)
        }.frame(width: size, height: size)
    }

    private var bar: some View {
        Capsule().fill(.quaternary)
            .frame(width: compact ? 26 : 36, height: 5)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(color).frame(width: proxy.size.width * min(1, max(0, fraction ?? 0)))
                }
            }
    }
}

#Preview("单行概览") {
    VStack(spacing: 0) {
        ForEach(MetricDisplayStyle.allCases, id: \.self) { style in
            SystemStrip(reading: SystemReading(cpuPercent: 18, gpuPercent: 64, thermalLabel: "正常",
                memory: .init(usedBytes: 14 * 1_073_741_824, totalBytes: 24 * 1_073_741_824, compressedBytes: 1_073_741_824, swapBytes: 512 * 1_048_576),
                network: .init(receiveRate: 12_345_678, sendRate: 123_456), temperatureCelsius: 74.3), style: style)
            Divider()
        }
    }.frame(width: 720)
}
