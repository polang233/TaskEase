import SwiftUI

/// 显示偏好、规则入口与数据清理操作。
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var confirmErase = false
    @State private var eraseError: String?

    var body: some View {
        Form {
            Section("settings.display") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("settings.language", selection: Binding(get: { model.language }, set: { model.setLanguage($0) })) {
                        ForEach(AppLanguage.allCases) { Text(verbatim: $0.title).tag($0) }
                    }.accessibilityIdentifier("app-language")
                    if model.languageNeedsRestart {
                        HStack(spacing: 8) {
                            Text("settings.language.restart").foregroundStyle(.secondary)
                            Button("settings.language.restartNow") { model.relaunch() }
                                .buttonStyle(.link).pointingHand()
                        }.font(.caption)
                    }
                }
                Picker("settings.theme", selection: Binding(get: { model.preferences.theme },
                                                 set: { theme in model.updatePreferences { $0.theme = theme } })) {
                    ForEach(ThemeMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }.selectionRail().accessibilityIdentifier("theme-mode")
                Picker("settings.metricStyle", selection: Binding(get: { model.preferences.metricStyle },
                    set: { style in model.updatePreferences { $0.metricStyle = style } })) {
                    ForEach(MetricDisplayStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }.selectionRail().accessibilityIdentifier("metric-style")
                VStack(alignment: .leading, spacing: 6) {
                    Picker("settings.cpuScale", selection: Binding(get: { model.preferences.cpuScale },
                        set: { scale in model.updatePreferences { $0.cpuScale = scale } })) {
                        ForEach(CPUScale.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.selectionRail().accessibilityIdentifier("cpu-scale")
                    Text("settings.cpuScale.note")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("settings.refreshInterval", selection: Binding(get: { model.preferences.refreshInterval },
                                                       set: { interval in model.updatePreferences { $0.refreshInterval = interval } })) {
                    ForEach(DisplayRefreshInterval.allCases, id: \.self) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("display-refresh-interval")
                Toggle("settings.foregroundOnly", isOn: Binding(get: { model.preferences.refreshOnlyInForeground },
                    set: { value in model.updatePreferences { $0.refreshOnlyInForeground = value } }))
                    .toggleStyle(.checkbox).accessibilityIdentifier("foreground-display-only")
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("settings.menuBarIcon", isOn: Binding(get: { model.preferences.showMenuBarIcon },
                        set: { value in model.updatePreferences { $0.showMenuBarIcon = value } }))
                        .toggleStyle(.checkbox).accessibilityIdentifier("show-menu-bar-icon")
                    if !model.preferences.showMenuBarIcon {
                        Text("settings.menuBarIcon.note").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle("settings.showSystemApps", isOn: Binding(get: { model.preferences.showSystemApps },
                                                   set: { value in model.updatePreferences { $0.showSystemApps = value } }))
                    .toggleStyle(.checkbox)
            }
            Section("settings.rules") {
                LabeledContent("settings.rules.saved", value: String(localized: "settings.rules.savedCount \(model.savedRuleCount)"))
                LabeledContent("settings.rules.enabled", value: String(localized: "settings.rules.enabledCount \(model.configuredCount)"))
                Button("settings.rules.manage") {
                    model.setApplicationList(.configured)
                    model.showManagement()
                }.accessibilityIdentifier("open-configured-rules")
            }
            Section("settings.experimental") {
                Toggle("settings.network", isOn: Binding(get: { model.preferences.networkFeaturesEnabled },
                    set: { value in model.updatePreferences { $0.networkFeaturesEnabled = value } }))
                    .toggleStyle(.checkbox).accessibilityIdentifier("network-features-enabled")
                Text("settings.network.note")
                    .font(.caption).foregroundStyle(.secondary)
                if model.preferences.networkFeaturesEnabled {
                    Toggle("settings.network.showSpeed", isOn: Binding(get: { model.preferences.showNetworkActivity },
                        set: { value in model.updatePreferences { $0.showNetworkActivity = value } }))
                        .toggleStyle(.checkbox).accessibilityIdentifier("show-network-activity")
                }
            }
            Section("settings.helpInfo") {
                HStack(spacing: 12) {
                    Button("common.help") { model.showUtility(.help) }
                    Button("menu.about") { model.showUtility(.about) }
                    Spacer()
                    Button("settings.erase", role: .destructive) { confirmErase = true }
                        .accessibilityIdentifier("erase-app-data")
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .alert("settings.erase.title", isPresented: $confirmErase) {
            Button("common.cancel", role: .cancel) { }
            Button("settings.erase.confirm", role: .destructive) { eraseError = model.eraseDataAndQuit() }
        } message: {
            Text("settings.erase.message")
        }
        .alert("settings.erase.failed", isPresented: Binding(get: { eraseError != nil }, set: { if !$0 { eraseError = nil } })) {
            Button("common.ok", role: .cancel) { eraseError = nil }
        } message: { Text(eraseError ?? "") }
    }
}

#Preview("设置") {
    SettingsView(model: AppModel(preview: true)).frame(width: 560, height: 700)
}
