import SwiftUI
import Charts

/// 使用统计窗口：公开的设备概况与本机匿名上报开关分开展示。
struct UsageStatisticsView: View {
    @Bindable var model: AppModel
    private var statistics: UsageStatisticsModel { model.usageStatistics }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("一起让后台更轻松～").font(.title2.weight(.semibold))
            overview
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Toggle("匿名使用统计", isOn: Binding(get: { model.usageAnalytics.enabled },
                    set: { model.usageAnalytics.setEnabled($0) }))
                    .toggleStyle(.switch).disabled(!model.usageAnalytics.isConfigured)
                    .accessibilityIdentifier("usage-analytics-toggle")
                Text("默认开启匿名使用统计，收集系统地区、版本等使用概况，不包含姓名、文件或其他应用明细。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("只是想看看有多少人在用轻程。上报低频且数据量很小，十分感谢！")
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
                    Text("近 30 天").foregroundStyle(.secondary)
                    Text("\(summary.activeInstallations)")
                        .font(.title.weight(.semibold)).monospacedDigit()
                        .accessibilityIdentifier("active-installation-count")
                    Text("台设备在用轻程").foregroundStyle(.secondary)
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
            BarMark(x: .value("日期", day.date, unit: .day), y: .value("设备", day.installations), width: .ratio(0.7))
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
        .accessibilityLabel("每日活跃设备趋势")
    }

    private func regions(_ regions: [PublicUsageSummary.Region], total: Int) -> some View {
        HStack(spacing: 14) {
            ForEach(regions.prefix(4), id: \.name) { region in
                HStack(spacing: 4) {
                    Text(region.name)
                    Text(total > 0 ? "\(Int((Double(region.installations) / Double(total) * 100).rounded()))%" : "\(region.installations)")
                        .foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }.font(.caption)
    }

    @ViewBuilder private func footer(_ updated: Date?) -> some View {
        if statistics.failed {
            HStack(spacing: 8) {
                Text("暂时无法读取统计。").foregroundStyle(.secondary)
                Button("重试", systemImage: "arrow.clockwise") { statistics.refresh(force: true) }
                    .buttonStyle(.link).disabled(statistics.loading).pointingHand()
                    .accessibilityIdentifier("refresh-public-statistics")
            }.font(.caption)
        } else if let updated {
            Text("更新于 \(updated.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }
}

#Preview("使用统计") {
    UsageStatisticsView(model: AppModel(preview: true)).frame(width: 580, height: 460)
}
