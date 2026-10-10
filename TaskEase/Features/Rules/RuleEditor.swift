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
                    if model.rules[app.id] != nil {
                        Button("移除规则", systemImage: "trash", role: .destructive) { model.resetRule(app.id) }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).help("移除规则")
                            .accessibilityIdentifier("remove-rule")
                    }
                }
                if app.isRunning {
                    HStack(spacing: 30) {
                        metric("CPU", value: Display.percent(app.cpuPercent))
                        metric("物理内存合计", value: Display.memory(app))
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
                if app.isRunning {
                    Divider()
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
                        }
                    }.padding(.top, 8)
                }.foregroundStyle(.secondary)
            }.padding(24)
        }
    }

    private var ruleControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("限制后台资源", isOn: Binding(get: { rule.isActive },
                                                set: { value in update { $0.mode = value ? .budget : .off } }))
                .toggleStyle(.switch).font(.headline).accessibilityIdentifier("app-rule-toggle")
            if rule.isActive {
                Stepper("离开前台 \(Int(rule.delaySeconds)) 秒后生效",
                        value: Binding(get: { rule.delaySeconds }, set: { delay in update { $0.delaySeconds = delay } }),
                        in: 0...300, step: 1)
                    .accessibilityIdentifier("background-delay")
                Text("失去前台焦点或隐藏后开始计时，切回前台恢复。")
                    .font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("CPU 使用上限")
                        Spacer()
                        Text("\(Int(rule.cpuPercent))%").monospacedDigit()
                    }
                    Slider(value: Binding(get: { rule.cpuPercent }, set: { percent in update { $0.cpuPercent = percent } }),
                           in: 5...200, step: 5).accessibilityIdentifier("cpu-budget")
                    Text("100% 约等于一个核心满载，按整个应用合计控制平均占用。")
                        .font(.caption).foregroundStyle(.secondary)
                }.disabled(rule.mode == .gentle)
                DisclosureGroup("高级选项") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("仅降低后台优先级", isOn: Binding(get: { rule.mode == .gentle },
                                                           set: { value in update { $0.mode = value ? .gentle : .budget } }))
                            .toggleStyle(.checkbox).accessibilityIdentifier("gentle-mode")
                        Text("让前台任务优先获得资源，没有固定 CPU 上限。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 10)
                }
                if rule.mode == .budget {
                    Label("CPU 限制会短暂暂停应用，也会影响声音和连接心跳。",
                          systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
                if !model.enabled {
                    Text("规则已保存，打开顶部总开关后执行。").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("保持原样").font(.callout).foregroundStyle(.secondary)
                Text("开启后设置等待时间和 CPU 使用上限。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2).monospacedDigit()
        }
    }

    private func readingRow(_ title: String, value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).monospacedDigit() }.font(.callout)
    }
}
