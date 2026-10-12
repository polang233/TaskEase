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
                Text("network.title").font(.headline)
                Spacer()
                if rule.isActive {
                    Label(model.networkStatus(for: app.id).title, systemImage: "clock")
                        .font(.caption).foregroundStyle(.orange)
                        .accessibilityIdentifier("network-rule-status")
                }
                if model.networkRules[app.id] != nil {
                    Button("network.remove") { model.removeNetworkRule(app.id) }
                        .buttonStyle(.borderless).font(.caption)
                        .accessibilityIdentifier("remove-network-rule")
                }
            }
            Text("network.note")
                .font(.caption).foregroundStyle(.secondary)
            Picker("network.mode", selection: Binding(get: { rule.mode }, set: { mode in update { $0.mode = mode } })) {
                ForEach(NetworkRuleMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }.accessibilityIdentifier("network-rule-mode")
                .disabled(!model.allowsRuleEditing(app))
            if rule.isActive {
                Picker("network.scope", selection: Binding(get: { rule.scope }, set: { scope in update { $0.scope = scope } })) {
                    ForEach(NetworkRuleScope.allCases, id: \.self) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("network-rule-scope")
                if rule.scope == .background {
                    Stepper("network.delay \(Int(rule.delaySeconds))",
                            value: Binding(get: { rule.delaySeconds }, set: { delay in update { $0.delaySeconds = delay } }),
                            in: 0...300, step: 1).accessibilityIdentifier("network-rule-delay")
                }
                if rule.mode == .limit {
                    HStack {
                        Text("network.downloadCap")
                        Spacer()
                        TextField("network.downloadCap", value: Binding(get: { rule.downloadKiBPerSecond },
                            set: { value in update { $0.downloadKiBPerSecond = value } }), format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder).frame(width: 90)
                            .accessibilityIdentifier("network-download-limit")
                        Text(verbatim: "KiB/s").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("network.uploadCap")
                        Spacer()
                        TextField("network.uploadCap", value: Binding(get: { rule.uploadKiBPerSecond },
                            set: { value in update { $0.uploadKiBPerSecond = value } }), format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder).frame(width: 90)
                            .accessibilityIdentifier("network-upload-limit")
                        Text(verbatim: "KiB/s").foregroundStyle(.secondary)
                    }
                }
                Text("network.saved")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.networkRuleError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
    }
}
