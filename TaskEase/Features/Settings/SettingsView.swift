import SwiftUI

/// 显示偏好、规则入口与数据清理操作。
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var confirmErase = false
    @State private var eraseError: String?

    var body: some View {
        Form {
            Section("显示") {
                Picker("外观", selection: Binding(get: { model.preferences.theme },
                                                 set: { theme in model.updatePreferences { $0.theme = theme } })) {
                    ForEach(ThemeMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }.selectionRail().accessibilityIdentifier("theme-mode")
                Picker("概览样式", selection: Binding(get: { model.preferences.metricStyle },
                    set: { style in model.updatePreferences { $0.metricStyle = style } })) {
                    ForEach(MetricDisplayStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }.selectionRail().accessibilityIdentifier("metric-style")
                VStack(alignment: .leading, spacing: 6) {
                    Picker("应用 CPU 口径", selection: Binding(get: { model.preferences.cpuScale },
                        set: { scale in model.updatePreferences { $0.cpuScale = scale } })) {
                        ForEach(CPUScale.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.selectionRail().accessibilityIdentifier("cpu-scale")
                    Text(model.preferences.cpuScale == .core ? "100% 为一个核心满载，与活动监视器一致。" : "占全部核心的比例，所有应用合计不超过 100%。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("数据刷新间隔", selection: Binding(get: { model.preferences.refreshInterval },
                                                       set: { interval in model.updatePreferences { $0.refreshInterval = interval } })) {
                    ForEach(DisplayRefreshInterval.allCases, id: \.self) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("display-refresh-interval")
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("管理窗口仅在前台刷新", isOn: Binding(get: { model.preferences.refreshOnlyInForeground },
                        set: { value in model.updatePreferences { $0.refreshOnlyInForeground = value } }))
                        .toggleStyle(.checkbox).accessibilityIdentifier("foreground-display-only")
                    Text("不影响后台规则执行。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("显示系统应用", isOn: Binding(get: { model.preferences.showSystemApps },
                                                   set: { value in model.updatePreferences { $0.showSystemApps = value } }))
                    .toggleStyle(.checkbox)
            }
            Section("后台规则") {
                LabeledContent("已保存", value: "\(model.savedRuleCount) 个应用")
                LabeledContent("已启用", value: "\(model.configuredCount) 条规则")
                Button("管理后台规则") {
                    model.setApplicationList(.configured)
                    model.showManagement()
                }.accessibilityIdentifier("open-configured-rules")
            }
            Section("实验功能") {
                Toggle("网络功能（测试）", isOn: Binding(get: { model.preferences.networkFeaturesEnabled },
                    set: { value in model.updatePreferences { $0.networkFeaturesEnabled = value } }))
                    .toggleStyle(.checkbox).accessibilityIdentifier("network-features-enabled")
                Text("显示应用网速与网络规则配置；阻断和限速尚未生效。")
                    .font(.caption).foregroundStyle(.secondary)
                if model.preferences.networkFeaturesEnabled {
                    Toggle("显示应用网络速度", isOn: Binding(get: { model.preferences.showNetworkActivity },
                        set: { value in model.updatePreferences { $0.showNetworkActivity = value } }))
                        .toggleStyle(.checkbox).accessibilityIdentifier("show-network-activity")
                }
            }
            Section("帮助与信息") {
                HStack(spacing: 12) {
                    Button("使用帮助") { model.showUtility(.help) }
                    Button("关于轻程") { model.showUtility(.about) }
                    Spacer()
                    Button("清除数据并退出…", role: .destructive) { confirmErase = true }
                        .accessibilityIdentifier("erase-app-data")
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .alert("清除数据并退出？", isPresented: $confirmErase) {
            Button("取消", role: .cancel) { }
            Button("清除并退出", role: .destructive) { eraseError = model.eraseDataAndQuit() }
        } message: {
            Text("将删除后台规则、显示设置及本地应用数据，并解除正在执行的限制。退出后可在访达中将轻程移到废纸篓。")
        }
        .alert("数据清理未完成", isPresented: Binding(get: { eraseError != nil }, set: { if !$0 { eraseError = nil } })) {
            Button("好", role: .cancel) { eraseError = nil }
        } message: { Text(eraseError ?? "") }
    }
}

#Preview("设置") {
    SettingsView(model: AppModel(preview: true)).frame(width: 560, height: 700)
}
