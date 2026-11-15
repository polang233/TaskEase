import SwiftUI
import AppKit

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
            VStack(alignment: .leading, spacing: 18) {
                header
                // 主要任务在前：规则卡片紧跟标题，占用与图表放在后面辅助判断。
                SectionCard {
                    ruleControls.disabled(!model.allowsRuleEditing(app))
                    if !model.allowsRuleEditing(app) {
                        Label(title: { app.isSystemApp ? Text("rule.readOnly.system") : Text("rule.readOnly.other") }, icon: { Image(systemName: "lock") })
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                if model.preferences.networkFeaturesEnabled {
                    SectionCard { NetworkRuleEditor(model: model, app: app) }
                }
                if app.isRunning {
                    let cpu = AppUsage.cpu(app, scale: model.preferences.cpuScale)
                    HStack(spacing: 10) {
                        statTile("metric.cpu", value: Display.percent(cpu),
                                 color: model.preferences.cpuScale == .machine ? MetricPalette.percent(cpu) : MetricPalette.applicationCPU(cpu))
                        statTile("metric.memory", value: Display.memory(app))
                    }
                    if model.effectiveSortKey != .name {
                        SectionCard {
                            HStack {
                                Text(model.effectiveSortKey.title).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("usage.chart.recent").font(.caption).foregroundStyle(.secondary)
                            }
                            UsageChart(key: model.effectiveSortKey, points: model.usageHistory.points(for: app.id),
                                       scale: model.preferences.cpuScale)
                        }
                    }
                }
                if app.isRunning {
                    if model.preferences.networkActivityVisible {
                        SectionCard(title: "rule.network.title") {
                            VStack(alignment: .leading, spacing: 10) {
                                readingRow("rule.network.receive", value: Display.networkRate(app.network?.receiveRate))
                                readingRow("rule.network.send", value: Display.networkRate(app.network?.sendRate))
                                Text(app.network?.sampledProcesses == 0 ? String(localized: "rule.network.none") : model.networkMonitorStatus.message)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.help("rule.network.help")
                    }
                    SectionCard(title: "rule.disk.title") {
                        VStack(alignment: .leading, spacing: 10) {
                            readingRow("rule.disk.read", value: Display.rate(app.readRate))
                            readingRow("rule.disk.write", value: Display.rate(app.writeRate))
                            readingRow("rule.wakeups", value: Display.wakeups(app.wakeupRate))
                                .help("rule.wakeups.help")
                        }
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
                    .padding(.horizontal, 4)
            }.padding(20)
        }
    }

    /// 应用标题：名称、当前状态与规则摘要；未运行时说明规则在下次运行时执行。
    private var header: some View {
        HStack(spacing: 12) {
            StatusIcon(app: app, status: app.status, size: 48)
            VStack(alignment: .leading, spacing: 5) {
                Text(app.name).font(.title3.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    StatusLabel(status: app.status)
                    if !app.isRunning {
                        Text("rule.notRunning").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer()
            if model.rules[app.id] != nil || model.networkRules[app.id] != nil {
                Button("rule.remove", systemImage: "trash", role: .destructive) { model.resetRule(app.id) }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).help("rule.remove").pointingHand()
                    .accessibilityIdentifier("remove-rule")
            }
        }
    }

    private var ruleControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("rule.toggle").font(.headline)
                    // 关闭时说明打开后会怎样，打开后用一句话概括当前规则。
                    Group {
                        if rule.isActive { Text(verbatim: rule.summary()) }
                        else { Text("rule.toggle.description") }
                    }
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("rule-summary")
                }
                Spacer()
                Toggle("rule.toggle", isOn: Binding(get: { rule.isEnabled }, set: { value in update { $0.isEnabled = value } }))
                    .toggleStyle(.switch).labelsHidden().accessibilityIdentifier("app-rule-toggle")
            }
            if rule.isActive && !model.enabled {
                enableCallout
            }
            if rule.isEnabled {
                Divider()
                timingControls
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("rule.mode").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    performanceControls
                    audioControls
                    switchRow("mode.gentle", systemImage: "tortoise", isOn: rule.lowersPriority && !rule.suspends,
                              identifier: "priority-toggle") { value in
                        update { $0.lowersPriority = value }
                    }.disabled(rule.suspends)
                }
            }
        }
    }

    /// 规则已有效但总开关关闭：就地说明并提供一键启用，不必回到页眉找开关。
    private var enableCallout: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(Color.accentColor)
            Text("rule.enableCallout").font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("toggle.enable") { model.setEnabled(true) }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .disabled(!model.canEnable).pointingHand()
                .accessibilityIdentifier("enable-from-rule")
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var timingControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("rule.timing")
                Spacer()
                Text(rule.timingTitle).monospacedDigit().foregroundStyle(rule.alwaysLimit ? .orange : .primary)
            }
            Slider(value: Binding(get: { Double(rule.delayIndex) }, set: { setDelay(index: Int($0.rounded())) }),
                   in: Double(minimumDelayIndex)...Double(AppRule.delayPresets.count - 1), step: 1)
                .accessibilityIdentifier("background-delay")
                .accessibilityValue(rule.timingTitle)
            let last = AppRule.delayPresets.count - 1
            SliderMarks(range: Double(minimumDelayIndex)...Double(last),
                        marks: [minimumDelayIndex, 2, 5, last].map { (Double($0), AppRule.shortDelayTitle(index: $0)) })
            if rule.alwaysLimit {
                Text("rule.timing.always.note").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var performanceControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            switchRow("rule.performance", systemImage: "cpu", isOn: rule.limitsPerformance, identifier: "performance-toggle") { value in
                update {
                    $0.limitsPerformance = value
                    if value { Self.leaveAlwaysForSuspend(&$0) }
                }
            }
            if rule.limitsPerformance {
                // 子设置向右缩进到标题文字处，表示属于上面的开关。
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("rule.cpuCap")
                        Spacer()
                        Text(rule.suspends ? String(localized: "mode.suspend") : "\(Int(rule.cpuPercent))%")
                            .monospacedDigit().foregroundStyle(rule.suspends ? .orange : .primary)
                    }.padding(.top, 4)
                    // 不设 step，避免 40 个刻度点；取值按 5% 取整，拖到最左为暂停应用。
                    Slider(value: Binding(get: { rule.suspends ? 0 : rule.cpuPercent }, set: setCPU), in: 0...200)
                        .accessibilityIdentifier("cpu-budget")
                        .accessibilityValue(rule.suspends ? Text("mode.suspend") : Text(verbatim: "\(Int(rule.cpuPercent))%"))
                    SliderMarks(range: 0...200, marks: [(0, String(localized: "rule.cpuCap.pause")),
                                                        (50, "50%"), (100, "100%"), (150, "150%"), (200, "200%")])
                    if rule.suspends {
                        Text("rule.mode.suspend.note").font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.leading, Self.nestedInset)
            }
        }
    }

    private var audioControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            switchRow("rule.audio", systemImage: "speaker.wave.2", isOn: rule.adjustsVolume && AppVolume.isSupported, identifier: "volume-toggle") { value in
                update { $0.adjustsVolume = value }
            }.disabled(!AppVolume.isSupported)
            if !AppVolume.isSupported {
                Text("rule.audio.unsupported").font(.caption).foregroundStyle(.secondary)
            } else {
                if rule.adjustsVolume {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("rule.volume")
                            Spacer()
                            Text(volumeTitle).monospacedDigit()
                        }.padding(.top, 4)
                        Slider(value: Binding(get: { rule.volumePercent }, set: { percent in
                            let rounded = (percent / 5).rounded() * 5
                            if rounded != rule.volumePercent { update { $0.volumePercent = rounded } }
                        }), in: 0...90)
                            .accessibilityIdentifier("background-volume")
                            .accessibilityValue(volumeTitle)
                        SliderMarks(range: 0...90, marks: [(0, String(localized: "rule.volume.mute")),
                                                           (30, "30%"), (60, "60%"), (90, "90%")])
                    }.padding(.leading, Self.nestedInset)
                }
                if rule.adjustsVolume && model.volumeFailures.contains(app.id) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("rule.audio.failed").font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("rule.audio.openSettings") { NSWorkspace.shared.open(Self.audioSettingsURL) }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    /// 符号宽度加间距，子设置与开关标题文字左对齐。
    private static let nestedInset: CGFloat = 28

    private var volumeTitle: String {
        rule.volumePercent == 0 ? String(localized: "rule.volume.mute") : "\(Int(rule.volumePercent))%"
    }

    /// CPU 上限滑杆按 5% 取整，0 表示暂停应用；暂停时保留原上限，拖回后继续使用。
    private func setCPU(_ percent: Double) {
        let rounded = (percent / 5).rounded() * 5
        update {
            if rounded == 0 {
                $0.performance = .suspend
                Self.leaveAlwaysForSuspend(&$0)
            } else {
                $0.performance = .budget
                $0.cpuPercent = rounded
            }
        }
    }

    private static let audioSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    /// 左侧带符号的标题、右侧开关的一行。
    private func switchRow(_ title: LocalizedStringKey, systemImage: String, isOn: Bool, identifier: String,
                           set: @escaping (Bool) -> Void) -> some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 20)
            }
            Spacer()
            Toggle(title, isOn: Binding(get: { isOn }, set: set))
                .toggleStyle(.switch).labelsHidden().accessibilityIdentifier(identifier)
        }
    }

    /// 暂停应用不能在前台生效，滑块从 1 秒开始。
    private var minimumDelayIndex: Int { rule.suspends ? 1 : 0 }

    /// 暂停不能始终生效；从始终限制切到暂停时改回默认的 3 秒。
    private static func leaveAlwaysForSuspend(_ rule: inout AppRule) {
        if rule.suspends && rule.alwaysLimit {
            rule.alwaysLimit = false
            rule.delaySeconds = 3
        }
    }

    private func setDelay(index: Int) {
        let presets = AppRule.delayPresets
        let index = min(presets.count - 1, max(minimumDelayIndex, index))
        guard index != rule.delayIndex else { return }
        update {
            $0.alwaysLimit = index == 0
            $0.delaySeconds = presets[index]
        }
    }

    /// 运行指标卡片：小标题加圆体大数字，与下方分组卡片同一底色。
    private func statTile(_ title: LocalizedStringKey, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit()
                .foregroundStyle(color).contentTransition(.numericText())
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }

    private func readingRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }.font(.callout)
    }
}

/// 滑杆下方的刻度标线与文字，按取值比例对齐；两端扣除滑块半径，首尾文字向内对齐。
struct SliderMarks: View {
    let range: ClosedRange<Double>
    let marks: [(value: Double, label: String)]
    private let inset: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - inset * 2
            ForEach(marks.indices, id: \.self) { index in
                let fraction = (marks[index].value - range.lowerBound) / (range.upperBound - range.lowerBound)
                let alignment: HorizontalAlignment = index == 0 ? .leading : index == marks.count - 1 ? .trailing : .center
                VStack(alignment: alignment, spacing: 2) {
                    Rectangle().frame(width: 1, height: 4)
                    Text(marks[index].label).font(.caption2).monospacedDigit().fixedSize()
                }
                // 宽度为 1 的框让标线落在刻度位置，文字按对齐方式向一侧展开。
                .frame(width: 1, alignment: Alignment(horizontal: alignment, vertical: .center))
                .foregroundStyle(.secondary)
                .position(x: inset + width * fraction, y: 10)
            }
        }
        .frame(height: 20).padding(.top, -6).accessibilityHidden(true)
    }
}
