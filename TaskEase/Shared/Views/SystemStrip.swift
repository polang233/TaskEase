import SwiftUI
import AppKit

/// 系统指标保持单行；指针移到 CPU、GPU、内存、温度或网络上时稍微放大并打开无箭头卡片，离开指标和卡片后立即关闭。
/// 点击指标把卡片固定在该指标下，固定期间悬停其他指标不再切换；再次点击、点到别处或窗口失焦时解除。
struct SystemStrip: View {
    let reading: SystemReading
    var isPaused = false
    var style: MetricDisplayStyle = .number
    @State private var active: SystemMetric?
    @State private var pinned: SystemMetric?
    @State private var hovered: SystemMetric?
    @State private var cards = HoverCardCoordinator()
    @State private var anchors: [SystemMetric: WeakAnchor] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(compact: false)
            row(compact: true)
        }.monospacedDigit().padding(.horizontal, 14).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isPaused ? Color.blue.opacity(0.04) : Color.clear)
            .onAppear { cards.onClose = { active = nil; pinned = nil } }
            .onDisappear { cards.close() }
            .onExitCommand { cards.close() }
            .onChange(of: reading) { refreshCard() }
            .onChange(of: isPaused) { refreshCard() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in cards.close() }
    }

    private func row(compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 20) {
            gauge(.cpu, compact: compact, value: Display.percent(reading.cpuPercent),
                  fraction: reading.cpuPercent.map { $0 / 100 })
            gauge(.gpu, compact: compact, value: Display.percent(reading.gpuPercent),
                  fraction: reading.gpuPercent.map { $0 / 100 })
            gauge(.memory, compact: compact, value: Display.percent(reading.memory?.percent),
                  fraction: reading.memory?.percent.map { $0 / 100 })
            gauge(.temperature, compact: compact,
                  value: reading.temperatureCelsius == nil ? reading.thermal.title : Display.temperature(reading.temperatureCelsius),
                  fraction: MetricPalette.thermalFraction(celsius: reading.temperatureCelsius),
                  color: MetricPalette.thermal(celsius: reading.temperatureCelsius, level: reading.thermal))
            cell(.network, label: Text("strip.network.a11y \(Display.compactRate(reading.network?.sendRate)) \(Display.compactRate(reading.network?.receiveRate))")) { _ in
                NetworkRateStack(reading: reading.network, compact: compact)
            }
            if isPaused {
                Image(systemName: "snowflake").font(.caption).foregroundStyle(.blue)
                    .help("strip.paused.help")
                    .accessibilityLabel("strip.paused").accessibilityIdentifier("display-paused")
            }
        }.fixedSize(horizontal: true, vertical: false)
    }

    private func gauge(_ kind: SystemMetric, compact: Bool, value: String, fraction: Double?, color: Color? = nil) -> some View {
        cell(kind, label: Text(kind.title) + Text(verbatim: " \(value)")) { isPinned in
            MetricGauge(kind: kind, value: value, fraction: fraction, color: color ?? MetricPalette.color(fraction),
                        style: style, compact: compact, emphasized: isPinned)
        }
    }

    /// 指标的公共外壳：悬停稍微放大并加浅底，固定时底色加深；点击固定或解除卡片。
    private func cell<Content: View>(_ kind: SystemMetric, label: Text,
                                     @ViewBuilder content: (Bool) -> Content) -> some View {
        let isPinned = pinned == kind
        let isHovered = hovered == kind
        return Button { isPinned ? cards.close() : pin(kind) } label: {
            content(isPinned)
                .padding(.horizontal, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(isPinned ? 0.07 : isHovered ? 0.045 : 0)))
                .scaleEffect(isPinned || isHovered ? 1.06 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.68), value: isPinned)
                .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.68), value: isHovered)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointingHand()
        .padding(.horizontal, -5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint(isPinned ? Text("strip.unpinHint") : Text("strip.pinHint"))
        .accessibilityAddTraits(isPinned ? .isSelected : [])
        .accessibilityIdentifier("system-\(kind.rawValue)")
        .background(AnchorReader { view in
            if anchors[kind]?.view !== view { anchors[kind] = WeakAnchor(view) }
        })
        .onHover { inside in
            if inside { hovered = kind } else if hovered == kind { hovered = nil }
            if inside && pinned == nil { open(kind) }
            cards.anchorHover(inside, id: kind)
        }
    }

    private func pin(_ kind: SystemMetric) {
        guard let anchor = anchors[kind]?.view else { return }
        active = kind
        cards.pin(anchor: anchor, content: details(kind), key: kind)
        if cards.isPinned { pinned = kind }
    }

    private func open(_ kind: SystemMetric) {
        guard active != kind || !cards.isOpen, let anchor = anchors[kind]?.view else { return }
        active = kind
        cards.show(anchor: anchor, content: details(kind), key: kind)
    }

    private func refreshCard() {
        guard let active, cards.isOpen else { return }
        cards.update(content: details(active))
    }

    private func details(_ kind: SystemMetric) -> AnyView {
        AnyView(MetricDetails(metric: kind, reading: reading, isPaused: isPaused))
    }
}

/// 单个指标的三种外观：数字、圆环、进度条（数值写在条内）。数值槽按最长内容预留宽度，避免数字变化时整行左右移动。
private struct MetricGauge: View {
    let kind: SystemMetric
    let value: String
    let fraction: Double?
    let color: Color
    let style: MetricDisplayStyle
    let compact: Bool
    /// 卡片固定在该指标时放大图标或圆环。
    var emphasized = false

    var body: some View {
        HStack(spacing: style == .bar ? 6 : 5) {
            switch style {
            case .number:
                Image(systemName: kind.symbol).foregroundStyle(emphasized ? color : .secondary)
                    .scaleEffect(emphasized ? 1.25 : 1)
                if !compact { Text(kind.title) }
                valueSlot
            case .ring:
                ring.scaleEffect(emphasized ? 1.2 : 1)
                if !compact { Text(kind.title) }
                valueSlot
            case .bar:
                Text(kind.title).foregroundStyle(compact ? .secondary : .primary)
                MetricBar(value: value, widestValues: kind.widestValues, fraction: fraction,
                          color: color, compact: compact)
            }
        }.font(compact ? .caption : .callout).frame(height: 24).fixedSize()
    }

    private var valueSlot: some View {
        ZStack(alignment: .leading) {
            ForEach(kind.widestValues, id: \.self) { Text($0).hidden() }
            Text(value).foregroundStyle(color)
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 3)
            Circle().trim(from: 0, to: min(1, max(0, fraction ?? 0)))
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }.frame(width: compact ? 14 : 16, height: compact ? 14 : 16)
    }
}

/// 条内显示数值的进度条：浅色底槽上铺指标色半透明填充，文字统一用主色保证对比度；宽度按最长数值预留。
private struct MetricBar: View {
    let value: String
    let widestValues: [String]
    let fraction: Double?
    let color: Color
    let compact: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: compact ? 4 : 5, style: .continuous)
        let filled = min(1, max(0, fraction ?? 0))
        ZStack {
            ForEach(widestValues, id: \.self) { label($0).hidden() }
            shape.fill(Color.primary.opacity(0.06))
            GeometryReader { proxy in
                shape.fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.5)],
                                          startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * filled)
            }
            label(value).foregroundStyle(.primary)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(color.opacity(0.35), lineWidth: 0.5))
        .frame(height: compact ? 16 : 18)
        .animation(.easeOut(duration: 0.35), value: filled)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: compact ? 10 : 11, weight: .semibold).monospacedDigit())
            .lineLimit(1)
            .padding(.horizontal, compact ? 7 : 9)
    }
}

#Preview("单行概览") {
    VStack(spacing: 0) {
        ForEach(MetricDisplayStyle.allCases, id: \.self) { style in
            SystemStrip(reading: SystemReading(cpuPercent: 18, gpuPercent: 64, thermal: .nominal,
                memory: .init(usedBytes: 14 * 1_073_741_824, totalBytes: 24 * 1_073_741_824, compressedBytes: 1_073_741_824, swapBytes: 512 * 1_048_576),
                network: .init(receiveRate: 12_345_678, sendRate: 123_456), temperatureCelsius: 74.3), style: style)
            Divider()
        }
    }.frame(width: 720)
}
