import SwiftUI

/// 编辑应用网络规则，并明确区分保存配置与系统控制能力。
struct NetworkRuleEditor: View {
    @Bindable var model: AppModel
    let app: AppReading
    private var rule: NetworkRule { model.networkRules[app.id] ?? NetworkRule() }

    private func update(_ change: (inout NetworkRule) -> Void) {
        var rule = rule
        change(&rule)
        model.setNetworkRule(app.id, rule: rule)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("网络规则").font(.headline)
                Spacer()
                if rule.isActive {
                    Label(model.networkStatus(for: app.id).title, systemImage: "clock")
                        .font(.caption).foregroundStyle(.orange)
                        .accessibilityIdentifier("network-rule-status")
                }
                if model.networkRules[app.id] != nil {
                    Button("移除网络规则") { model.removeNetworkRule(app.id) }
                        .buttonStyle(.borderless).font(.caption)
                        .accessibilityIdentifier("remove-network-rule")
                }
            }
            Text("测试功能：暂缺开发者账号签名，网络阻断和限速尚未实现。")
                .font(.caption).foregroundStyle(.secondary)
            Picker("联网方式", selection: Binding(get: { rule.mode }, set: { mode in update { $0.mode = mode } })) {
                ForEach(NetworkRuleMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }.accessibilityIdentifier("network-rule-mode")
                .disabled(!model.allowsRuleEditing(app))
            if rule.isActive {
                Picker("作用时间", selection: Binding(get: { rule.scope }, set: { scope in update { $0.scope = scope } })) {
                    ForEach(NetworkRuleScope.allCases, id: \.self) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("network-rule-scope")
                if rule.scope == .background {
                    Stepper("离开前台 \(Int(rule.delaySeconds)) 秒后生效",
                            value: Binding(get: { rule.delaySeconds }, set: { delay in update { $0.delaySeconds = delay } }),
                            in: 0...300, step: 1).accessibilityIdentifier("network-rule-delay")
                }
                if rule.mode == .limit {
                    HStack {
                        Text("下载上限")
                        Spacer()
                        TextField("下载上限", value: Binding(get: { rule.downloadKiBPerSecond },
                            set: { value in update { $0.downloadKiBPerSecond = value } }), format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder).frame(width: 90)
                            .accessibilityIdentifier("network-download-limit")
                        Text("KiB/s").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("上传上限")
                        Spacer()
                        TextField("上传上限", value: Binding(get: { rule.uploadKiBPerSecond },
                            set: { value in update { $0.uploadKiBPerSecond = value } }), format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder).frame(width: 90)
                            .accessibilityIdentifier("network-upload-limit")
                        Text("KiB/s").foregroundStyle(.secondary)
                    }
                }
                Text("已保存测试配置。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.networkRuleError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
    }
}
