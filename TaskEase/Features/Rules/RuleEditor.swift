import SwiftUI

/// 编辑单个应用的后台规则，所有变更通过 AppModel 保存与执行。
struct RuleEditor: View {
    @Bindable var model: AppModel
    let app: AppReading
    private var rule: AppRule { model.rules[app.id] ?? AppRule() }

    private func update(_ mutate: (inout AppRule) -> Void) {
        var changed = rule
        mutate(&changed)
        model.setRule(app.id, rule: changed)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    AppIcon(app: app, size: 44)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(app.name).font(.title3.weight(.semibold))
                        StatusLabel(status: app.status)
                    }
                    Spacer()
                    if model.rules[app.id] != nil || model.networkRules[app.id] != nil {
                        Button("rule.remove", systemImage: "trash", role: .destructive) { model.resetRule(app.id) }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).help("rule.remove").pointingHand()
                            .accessibilityIdentifier("remove-rule")
                    }
                }
                if app.isRunning {
                    HStack(spacing: 30) {
                        metric("metric.cpu", value: Display.percent(AppUsage.cpu(app, scale: model.preferences.cpuScale)))
                        metric("metric.memory", value: Display.memory(app))
                    }
                } else {
                    Text("rule.notRunning").font(.callout).foregroundStyle(.secondary)
                }
                Divider()
                ruleControls.disabled(!model.allowsRuleEditing(app))
                if !model.allowsRuleEditing(app) {
                    Label(title: { app.isSystemApp ? Text("rule.readOnly.system") : Text("rule.readOnly.other") }, icon: { Image(systemName: "lock") })
                        .font(.callout).foregroundStyle(.secondary)
                }
                if model.preferences.networkFeaturesEnabled {
                    Divider()
                    NetworkRuleEditor(model: model, app: app)
                }
                if app.isRunning {
                    Divider()
                    if model.preferences.networkActivityVisible {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("rule.network.title").font(.headline)
                            readingRow("rule.network.receive", value: Display.networkRate(app.network?.receiveRate))
                            readingRow("rule.network.send", value: Display.networkRate(app.network?.sendRate))
                            Text(app.network?.sampledProcesses == 0 ? String(localized: "rule.network.none") : model.networkMonitorStatus.message)
                                .font(.caption).foregroundStyle(.secondary)
                        }.help("rule.network.help")
                        Divider()
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("rule.disk.title").font(.headline)
                        readingRow("rule.disk.read", value: Display.rate(app.readRate))
                        readingRow("rule.disk.write", value: Display.rate(app.writeRate))
                        readingRow("rule.wakeups", value: Display.wakeups(app.wakeupRate))
                            .help("rule.wakeups.help")
                    }
                }
                DisclosureGroup("rule.processInfo") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(app.id).font(.caption).textSelection(.enabled)
                        ForEach(app.samples, id: \.identity) { process in
                            HStack {
                                Text(verbatim: "PID \(process.identity.pid)")
                                Spacer()
                                Text(Display.bytes(process.memoryBytes))
                            }.font(.caption).monospacedDigit()
                            if model.preferences.networkActivityVisible {
                                HStack {
                                    Text("rule.process.receive \(Display.networkRate(app.processNetwork[process.identity]?.receiveRate))")
                                    Spacer()
                                    Text("rule.process.send \(Display.networkRate(app.processNetwork[process.identity]?.sendRate))")
                                }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }.padding(.top, 8)
                }.disclosureGroupStyle(FullRowDisclosureStyle()).foregroundStyle(.secondary).pointingHand()
            }.padding(24)
        }
    }

    private var ruleControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("rule.toggle", isOn: Binding(get: { rule.isActive },
                                                set: { value in update { $0.mode = value ? .budget : .off } }))
                .toggleStyle(.switch).font(.headline).accessibilityIdentifier("app-rule-toggle")
            if rule.isActive {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("rule.mode", selection: Binding(get: { rule.mode }, set: { setMode($0) })) {
                        ForEach(ControlMode.limits, id: \.self) { Text($0.title).tag($0) }
                    }.selectionRail().accessibilityIdentifier("control-mode")
                    Text(modeNote).font(.caption).foregroundStyle(rule.mode == .suspend ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("rule.timing")
                        Spacer()
                        Text(delayTitle).monospacedDigit().foregroundStyle(rule.alwaysLimit ? .orange : .primary)
                    }
                    Slider(value: Binding(get: { Double(delayIndex) }, set: { setDelay(index: Int($0.rounded())) }),
                           in: Double(minimumDelayIndex)...Double(AppRule.delayPresets.count - 1), step: 1)
                        .accessibilityIdentifier("background-delay")
                        .accessibilityValue(delayTitle)
                    (rule.alwaysLimit ? Text("rule.timing.always.note") : Text("rule.timing.background.note"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if rule.mode == .budget {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("rule.cpuCap")
                            Spacer()
                            Text(verbatim: "\(Int(rule.cpuPercent))%").monospacedDigit()
                        }
                        Slider(value: Binding(get: { rule.cpuPercent }, set: { percent in update { $0.cpuPercent = percent } }),
                               in: 5...200, step: 5).accessibilityIdentifier("cpu-budget")
                        Text("rule.cpuCap.note")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !model.enabled {
                    Text("rule.enableHint").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var modeNote: LocalizedStringKey {
        switch rule.mode {
        case .gentle: "rule.mode.gentle.note"
        case .suspend: "rule.mode.suspend.note"
        default: "rule.mode.budget.note"
        }
    }

    /// 暂停应用不能在前台生效，滑块从 1 秒开始。
    private var minimumDelayIndex: Int { rule.mode == .suspend ? 1 : 0 }

    private func setMode(_ mode: ControlMode) {
        update {
            $0.mode = mode
            if mode == .suspend && $0.alwaysLimit {
                $0.alwaysLimit = false
                $0.delaySeconds = 3
            }
        }
    }

    /// 旧规则的等待时间可能不在预设中，显示最接近的档位。
    private var delayIndex: Int {
        if rule.alwaysLimit { return 0 }
        let presets = AppRule.delayPresets
        return (1..<presets.count).min { abs(presets[$0] - rule.delaySeconds) < abs(presets[$1] - rule.delaySeconds) } ?? 2
    }

    private var delayTitle: String {
        if rule.alwaysLimit { return String(localized: "rule.timing.always") }
        let seconds = Int(AppRule.delayPresets[delayIndex])
        return seconds >= 60 ? String(localized: "rule.timing.minutes \(seconds / 60)") : String(localized: "rule.timing.seconds \(seconds)")
    }

    private func setDelay(index: Int) {
        let presets = AppRule.delayPresets
        let index = min(presets.count - 1, max(minimumDelayIndex, index))
        guard index != delayIndex else { return }
        update {
            $0.alwaysLimit = index == 0
            $0.delaySeconds = presets[index]
        }
    }

    private func metric(_ title: LocalizedStringKey, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2).monospacedDigit().foregroundStyle(color)
        }
    }

    private func readingRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).monospacedDigit() }.font(.callout)
    }
}
