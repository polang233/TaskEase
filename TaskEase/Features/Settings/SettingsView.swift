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
                }.pickerStyle(.segmented).accessibilityIdentifier("theme-mode")
                Picker("数据刷新间隔", selection: Binding(get: { model.preferences.refreshInterval },
                                                       set: { interval in model.updatePreferences { $0.refreshInterval = interval } })) {
                    ForEach(DisplayRefreshInterval.allCases, id: \.self) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("display-refresh-interval")
                Toggle("管理窗口仅在前台刷新", isOn: Binding(get: { model.preferences.refreshOnlyInForeground },
                    set: { value in model.updatePreferences { $0.refreshOnlyInForeground = value } }))
                    .toggleStyle(.checkbox).accessibilityIdentifier("foreground-display-only")
                Toggle("显示应用网络速度", isOn: Binding(get: { model.preferences.showNetworkActivity },
                    set: { value in model.updatePreferences { $0.showNetworkActivity = value } }))
                    .toggleStyle(.checkbox).accessibilityIdentifier("show-network-activity")
                Toggle("显示系统应用", isOn: Binding(get: { model.preferences.showSystemApps },
                                                   set: { value in model.updatePreferences { $0.showSystemApps = value } }))
                    .toggleStyle(.checkbox)
                Text("切到后台时暂停管理窗口刷新；打开菜单栏面板时更新数据。后台规则继续执行。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("后台规则") {
                LabeledContent("已保存", value: "\(model.savedRuleCount) 个应用")
                LabeledContent("可启用", value: "\(model.configuredCount) 条规则")
                Button("管理后台规则") {
                    model.setApplicationList(.configured)
                    model.showManagement()
                }.accessibilityIdentifier("open-configured-rules")
            }
            Section("应用数据") {
                Button("清除数据并退出…", role: .destructive) { confirmErase = true }
                    .accessibilityIdentifier("erase-app-data")
            }
            Section("帮助与信息") {
                HStack(spacing: 16) {
                    Button("使用帮助") { model.showUtility(.help) }
                    Button("关于轻程") { model.showUtility(.about) }
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .preferredColorScheme(model.preferences.theme.colorScheme)
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
