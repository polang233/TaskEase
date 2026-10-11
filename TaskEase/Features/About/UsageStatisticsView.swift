import SwiftUI

/// 使用统计窗口：公开的设备概况与本机匿名上报开关分开展示。
struct UsageStatisticsView: View {
    @Bindable var model: AppModel
    private var statistics: UsageStatisticsModel { model.usageStatistics }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("一起让后台更轻松").font(.title2.weight(.semibold))
                Text("近 30 天活跃设备").font(.callout).foregroundStyle(.secondary)
                if statistics.loading && statistics.summary == nil {
                    ProgressView().frame(height: 58)
                } else {
                    Text(statistics.summary.map { "\($0.activeInstallations)" } ?? "—")
                        .font(.system(size: 48, weight: .semibold, design: .rounded)).monospacedDigit()
                        .accessibilityIdentifier("active-installation-count")
                }
                Text("按匿名安装标识估计设备数量；重新安装可能产生新的标识。")
                    .font(.caption).foregroundStyle(.secondary)
                if statistics.failed {
                    Text("暂时无法读取统计，请稍后刷新。").font(.caption).foregroundStyle(.secondary)
                } else if let updated = statistics.summary?.updatedAt {
                    Text("数据更新于 \(updated.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Link("查看趋势与地区分布", destination: ProjectLinks.statistics)
                    Spacer()
                    Button("刷新", systemImage: "arrow.clockwise") { statistics.refresh(force: true) }
                        .disabled(statistics.loading).accessibilityIdentifier("refresh-public-statistics")
                }.font(.callout)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Toggle("匿名使用统计", isOn: Binding(get: { model.usageAnalytics.enabled },
                    set: { model.usageAnalytics.setEnabled($0) }))
                    .toggleStyle(.switch).disabled(!model.usageAnalytics.isConfigured)
                    .accessibilityIdentifier("usage-analytics-toggle")
                Text("匿名上传使用概况，不包含个人信息或其他应用明细。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("默认开启，可随时关闭。关闭后停止本机上报，仍可查看公开统计。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview("使用统计") {
    UsageStatisticsView(model: AppModel(preview: true)).frame(width: 580, height: 460)
}
