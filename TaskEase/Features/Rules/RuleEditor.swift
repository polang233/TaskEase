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
                        Button("移除规则", systemImage: "trash", role: .destructive) { model.resetRule(app.id) }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).help("移除规则").pointingHand()
                            .accessibilityIdentifier("remove-rule")
                    }
                }
                if app.isRunning {
                    HStack(spacing: 30) {
                        metric("CPU", value: Display.percent(AppUsage.cpu(app, scale: model.preferences.cpuScale)))
                        metric("内存", value: Display.memory(app))
                    }
                } else {
                    Text("应用下次运行时按此规则执行。").font(.callout).foregroundStyle(.secondary)
                }
                Divider()
                ruleControls.disabled(!model.allowsRuleEditing(app))
                if !model.allowsRuleEditing(app) {
                    Label(app.isSystemApp ? "系统应用只用于观察。" : "该应用当前只支持占用观察。",
                          systemImage: "lock").font(.callout).foregroundStyle(.secondary)
                }
                if model.preferences.networkFeaturesEnabled {
                    Divider()
                    NetworkRuleEditor(model: model, app: app)
                }
                if app.isRunning {
                    Divider()
                    if model.preferences.networkActivityVisible {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("网络收发").font(.headline)
                            readingRow("接收速度", value: Display.networkRate(app.network?.receiveRate))
                            readingRow("发送速度", value: Display.networkRate(app.network?.sendRate))
                            Text(app.network?.sampledProcesses == 0 ? "当前没有系统网络计数" : model.networkMonitorStatus.message)
                                .font(.caption).foregroundStyle(.secondary)
                        }.help("应用自有进程的系统网络计数。共享代理、系统代发与短连接可能无法完整归属；第一帧需要建立速度基线。")
                        Divider()
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("磁盘与唤醒").font(.headline)
                        readingRow("磁盘读取", value: Display.rate(app.readRate))
                        readingRow("磁盘写入", value: Display.rate(app.writeRate))
                        readingRow("中断唤醒", value: Display.wakeups(app.wakeupRate))
                            .help("应用及其自有辅助进程每秒的中断唤醒次数。")
                    }
                }
                DisclosureGroup("应用与进程信息") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(app.id).font(.caption).textSelection(.enabled)
                        ForEach(app.samples, id: \.identity) { process in
                            HStack {
                                Text("PID \(process.identity.pid)")
                                Spacer()
                                Text(Display.bytes(process.memoryBytes))
                            }.font(.caption).monospacedDigit()
                            if model.preferences.networkActivityVisible {
                                HStack {
                                    Text("接收 " + Display.networkRate(app.processNetwork[process.identity]?.receiveRate))
                                    Spacer()
                                    Text("发送 " + Display.networkRate(app.processNetwork[process.identity]?.sendRate))
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
            Toggle("限制后台资源", isOn: Binding(get: { rule.isActive },
                                                set: { value in update { $0.mode = value ? .budget : .off } }))
                .toggleStyle(.switch).font(.headline).accessibilityIdentifier("app-rule-toggle")
            if rule.isActive {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("限制方式", selection: Binding(get: { rule.mode }, set: { setMode($0) })) {
                        ForEach(ControlMode.limits, id: \.self) { Text($0.title).tag($0) }
                    }.selectionRail().accessibilityIdentifier("control-mode")
                    Text(modeNote).font(.caption).foregroundStyle(rule.mode == .suspend ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("生效时机")
                        Spacer()
                        Text(delayTitle).monospacedDigit().foregroundStyle(rule.alwaysLimit ? .orange : .primary)
                    }
                    Slider(value: Binding(get: { Double(delayIndex) }, set: { setDelay(index: Int($0.rounded())) }),
                           in: Double(minimumDelayIndex)...Double(AppRule.delayPresets.count - 1), step: 1)
                        .accessibilityIdentifier("background-delay")
                        .accessibilityValue(delayTitle)
                    Text(rule.alwaysLimit ? "前台使用时也限制，操作可能不流畅。" : "切走或隐藏后开始计时，回到前台立即恢复。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if rule.mode == .budget {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("CPU 使用上限")
                            Spacer()
                            Text("\(Int(rule.cpuPercent))%").monospacedDigit()
                        }
                        Slider(value: Binding(get: { rule.cpuPercent }, set: { percent in update { $0.cpuPercent = percent } }),
                               in: 5...200, step: 5).accessibilityIdentifier("cpu-budget")
                        Text("100% 为一个核心满载，含应用的辅助进程。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !model.enabled {
                    Text("打开顶部总开关后生效。").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var modeNote: String {
        switch rule.mode {
        case .gentle: "降低调度优先级，前台应用优先获得资源；不设上限，空闲时占用可能不变。"
        case .suspend: "完全暂停，不占用 CPU。后台播放、下载和消息通知都会停止，回到前台后恢复。"
        default: "按上限短暂暂停应用，平均占用不超过设定值；可能影响声音和网络连接。"
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
        if rule.alwaysLimit { return "始终限制" }
        let seconds = Int(AppRule.delayPresets[delayIndex])
        return seconds >= 60 ? "离开前台 \(seconds / 60) 分钟后" : "离开前台 \(seconds) 秒后"
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

    private func metric(_ title: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2).monospacedDigit().foregroundStyle(color)
        }
    }

    private func readingRow(_ title: String, value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).monospacedDigit() }.font(.callout)
    }
}
