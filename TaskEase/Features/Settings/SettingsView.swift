import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

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
                Toggle("显示系统应用", isOn: Binding(get: { model.preferences.showSystemApps },
                                                   set: { value in model.updatePreferences { $0.showSystemApps = value } }))
                    .toggleStyle(.checkbox)
                Text("数据面板不可见时按需采样。刷新间隔只影响显示更新。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("后台规则") {
                LabeledContent("已保存", value: "\(model.rules.count) 条规则")
                LabeledContent("可启用", value: "\(model.configuredCount) 条规则")
                Button("管理后台规则") {
                    model.setApplicationList(.configured)
                    model.showManagement()
                }.accessibilityIdentifier("open-configured-rules")
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
    }
}

#Preview("设置") {
    SettingsView(model: AppModel(preview: true)).frame(width: 560, height: 510)
}
