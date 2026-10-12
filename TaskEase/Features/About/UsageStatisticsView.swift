import SwiftUI
import Charts

/// 使用统计窗口：公开的设备概况与本机匿名上报开关分开展示。
struct UsageStatisticsView: View {
    @Bindable var model: AppModel
    private var statistics: UsageStatisticsModel { model.usageStatistics }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("stats.title").font(.title2.weight(.semibold))
            overview
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Toggle("stats.toggle", isOn: Binding(get: { model.usageAnalytics.enabled },
                    set: { model.usageAnalytics.setEnabled($0) }))
                    .toggleStyle(.switch).disabled(!model.usageAnalytics.isConfigured)
                    .accessibilityIdentifier("usage-analytics-toggle")
                Text("stats.privacy")
                    .font(.caption).foregroundStyle(.secondary)
                Text("stats.thanks")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var overview: some View {
        if statistics.loading && statistics.summary == nil {
            ProgressView().frame(maxWidth: .infinity, minHeight: 150)
        } else if let summary = statistics.summary {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("stats.period").foregroundStyle(.secondary)
                    Text(summary.activeInstallations, format: .number)
                        .font(.title.weight(.semibold)).monospacedDigit()
                        .accessibilityIdentifier("active-installation-count")
                    (summary.activeInstallations == 1 ? Text("stats.devices.one") : Text("stats.devices.other")).foregroundStyle(.secondary)
                }
                if !summary.days.isEmpty { trend(summary.days) }
                if !summary.regions.isEmpty { regions(summary.regions, total: summary.activeInstallations) }
                footer(summary.updatedAt)
            }
        } else {
            footer(nil).frame(maxWidth: .infinity, minHeight: 150)
        }
    }

    private func trend(_ days: [PublicUsageSummary.Day]) -> some View {
        Chart(days, id: \.date) { day in
            BarMark(x: .value("stats.chart.date", day.date, unit: .day), y: .value("stats.chart.devices", day.installations), width: .ratio(0.7))
                .foregroundStyle(Color.accentColor.opacity(0.75))
                .cornerRadius(2)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: false)
            }
        }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
        .frame(height: 90)
        .accessibilityLabel("stats.chart.label")
    }

    private func regions(_ regions: [PublicUsageSummary.Region], total: Int) -> some View {
        HStack(spacing: 14) {
            ForEach(regions.prefix(4), id: \.name) { region in
                HStack(spacing: 4) {
                    Text(region.name)
                    Text(verbatim: total > 0
                         ? (Double(region.installations) / Double(total)).formatted(.percent.precision(.fractionLength(0)))
                         : region.installations.formatted())
                        .foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }.font(.caption)
    }

    @ViewBuilder private func footer(_ updated: Date?) -> some View {
        if statistics.failed {
            HStack(spacing: 8) {
                Text("stats.failed").foregroundStyle(.secondary)
                Button("common.retry", systemImage: "arrow.clockwise") { statistics.refresh(force: true) }
                    .buttonStyle(.link).disabled(statistics.loading).pointingHand()
                    .accessibilityIdentifier("refresh-public-statistics")
            }.font(.caption)
        } else if let updated {
            Text("stats.updated \(updated.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }
}

#Preview("使用统计") {
    UsageStatisticsView(model: AppModel(preview: true)).frame(width: 580, height: 460)
}
