import SwiftUI
import AppKit
import Charts

/// 节省报告窗口：今天与最近 7 天估算省下的 CPU / GPU 时间、按应用排行与估算口径。
struct SavingsReportView: View {
    @Bindable var model: AppModel
    @State private var confirmReset = false

    private var savings: SavingsModel { model.savings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    BrandMark(size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("savings.title").font(.title2.weight(.semibold))
                        Text("savings.subtitle").font(.callout).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    summaryTile("savings.today", amount: savings.today)
                    summaryTile("savings.week", amount: savings.week)
                }
                SectionCard(title: "savings.chart.title") {
                    chart.frame(height: 120)
                }
                SectionCard(title: "savings.ranking.title") { ranking }
                SectionCard(title: "savings.method.title") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Self.method.indices, id: \.self) { index in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(verbatim: "•").foregroundStyle(.secondary)
                                Text(Self.method[index]).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }.font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("savings.reset", role: .destructive) { confirmReset = true }
                        .accessibilityIdentifier("reset-savings")
                }
            }.padding(24)
        }
        .alert("savings.reset.title", isPresented: $confirmReset) {
            Button("common.cancel", role: .cancel) { }
            Button("savings.reset.confirm", role: .destructive) { savings.reset() }
        } message: { Text("savings.reset.message") }
    }

    private static let method: [LocalizedStringKey] = [
        "savings.method.1", "savings.method.2", "savings.method.3", "savings.method.4", "savings.method.5"
    ]

    private func summaryTile(_ title: LocalizedStringKey, amount: SavingsAmount) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(SavingsFormat.duration(amount.cpuSeconds))
                .font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit()
                .foregroundStyle(Color.green)
            Text("savings.cpuTime").font(.caption).foregroundStyle(.secondary)
            Text(SavingsFormat.details(amount)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }

    private var chart: some View {
        let days = savings.ledger.daily(7, endingAt: Date())
        return Chart(days, id: \.day) { item in
            BarMark(x: .value("day", item.day, unit: .day), y: .value("minutes", item.amount.cpuSeconds / 60))
                .foregroundStyle(Color.green.gradient)
                .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel { if let minutes = value.as(Double.self) { Text(SavingsFormat.duration(minutes * 60)) } }
            }
        }
        .accessibilityLabel("savings.chart.title")
    }

    @ViewBuilder private var ranking: some View {
        let entries = savings.entries(days: 7)
        if entries.isEmpty {
            Text("savings.empty").font(.callout).foregroundStyle(.secondary)
        } else {
            let peak = max(1, entries.map(\.amount.cpuSeconds).max() ?? 1)
            VStack(spacing: 2) {
                ForEach(entries) { entry in
                    HStack(spacing: 10) {
                        AppIcon(app: model.reportApplication(id: entry.id, name: entry.name), size: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).lineLimit(1)
                            Text(SavingsFormat.details(entry.amount)).font(.caption).foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Spacer()
                        Text(SavingsFormat.duration(entry.amount.cpuSeconds)).monospacedDigit()
                    }
                    .padding(.vertical, 5).padding(.horizontal, 6)
                    .background(UsageFill(fraction: entry.amount.cpuSeconds / peak))
                    .help(entry.amount.cpuSeconds == 0 ? String(localized: "savings.noBaseline") : "")
                }
            }
        }
    }
}

/// 节省数值的格式：时长按系统语言缩写，最多两个单位。
@MainActor
enum SavingsFormat {
    private static let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()

    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 1 else { return formatter.string(from: 0) ?? "0" }
        return formatter.string(from: seconds.rounded()) ?? "—"
    }

    /// 次要信息：GPU 时间（只在暂停期间估算）与受限时长。
    static func details(_ amount: SavingsAmount) -> String {
        var parts: [String] = []
        if amount.gpuSeconds >= 1 { parts.append(String(localized: "savings.gpu \(duration(amount.gpuSeconds))")) }
        parts.append(String(localized: "savings.limited \(duration(amount.limitedSeconds))"))
        return parts.joined(separator: " · ")
    }
}

/// 页眉与菜单栏面板的节省入口：有记录时显示今天省下的 CPU 时间，点击打开节省报告。
struct SavingsBadge: View {
    @Bindable var model: AppModel
    var compact = false

    var body: some View {
        let today = model.savings.today
        Button { model.showUtility(.savings) } label: {
            HStack(spacing: 4) {
                Image(systemName: "leaf.fill").foregroundStyle(.green)
                if !compact || today.cpuSeconds >= 1 {
                    Text(today.cpuSeconds >= 1 ? String(localized: "savings.badge \(SavingsFormat.duration(today.cpuSeconds))")
                         : String(localized: "savings.open"))
                        .lineLimit(1).fixedSize()
                }
            }.font(.caption).foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless).pointingHand()
        .help("savings.open")
        .accessibilityIdentifier("open-savings")
    }
}

#Preview("节省报告") {
    SavingsReportView(model: AppModel(preview: true)).frame(width: 560, height: 680)
}
