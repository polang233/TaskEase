import SwiftUI
import AppKit

enum Display {
    static func percent(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0) } ?? "—" }
    static func bytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(min(value, UInt64(Int64.max))))
    }
    static func memory(_ app: AppReading) -> String {
        app.samples.isEmpty && app.memoryBytes == 0 ? "—" : bytes(app.memoryBytes)
    }
    static func rate(_ value: Double) -> String { bytes(UInt64(max(0, value))) + "/s" }
}

struct AppIcon: View {
    let app: AppReading
    var size: CGFloat = 32
    var body: some View {
        Group {
            if let path = app.bundlePaths.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
            } else {
                Image(systemName: "app").resizable().scaledToFit().padding(5).foregroundStyle(.secondary)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct StatusLabel: View {
    let status: RuleStatus
    private var color: Color {
        switch status {
        case .gentle, .budget: return .green
        case .waiting: return .orange
        default: return .secondary
        }
    }
    var body: some View {
        Text(status.title).font(.caption).foregroundStyle(color)
    }
}

struct SystemStrip: View {
    let reading: SystemReading
    var body: some View {
        HStack(spacing: 18) {
            Label("CPU \(Display.percent(reading.cpuPercent))", systemImage: "cpu")
                .monospacedDigit()
            Label("GPU \(Display.percent(reading.gpuPercent))", systemImage: "square.3.layers.3d")
                .monospacedDigit()
                .help("整机 GPU 驱动利用率估计值，不能归属某个应用。缺失时显示 —。")
            Spacer(minLength: 10)
            Label(reading.thermalLabel, systemImage: "thermometer.medium")
                .foregroundStyle(reading.thermalLabel == "正常" ? Color.secondary : Color.orange)
        }.font(.callout).padding(.horizontal, 20).padding(.vertical, 11)
    }
}

struct ContentView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "leaf.fill").font(.title2).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("轻程").font(.title2.weight(.semibold))
                    Text("TaskEase").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.managedCount) 个应用正在管理").font(.callout).foregroundStyle(.secondary)
                Toggle("自动管理", isOn: Binding(get: { model.enabled }, set: { model.setEnabled($0) }))
                    .toggleStyle(.switch).accessibilityIdentifier("management-toggle")
            }.padding(20)
            Divider()
            SystemStrip(reading: model.system)
            Divider()
            if let error = model.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(error).font(.callout)
                    Spacer()
                    Button("恢复并重试") { model.setEnabled(true) }
                }.padding(12).background(Color.orange.opacity(0.08))
            }
            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索应用", text: $model.search)
                            .textFieldStyle(.plain).accessibilityIdentifier("app-search")
                        if !model.search.isEmpty {
                            Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                    }.padding(12)
                    Divider()
                    if model.filteredApps.isEmpty {
                        ContentUnavailableView("没有匹配的应用", systemImage: "magnifyingglass",
                                               description: Text("尝试其他名称，或等待应用启动。"))
                    } else {
                        List(selection: $model.selectedID) {
                            ForEach(model.filteredApps) { app in
                                HStack(spacing: 10) {
                                    AppIcon(app: app)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(app.name).lineLimit(1)
                                        HStack {
                                            StatusLabel(status: app.status)
                                            if !app.targets.isEmpty { Text("\(app.targets.count) 个进程").font(.caption).foregroundStyle(.tertiary) }
                                        }
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(Display.percent(app.cpuPercent)).monospacedDigit()
                                        Text(Display.memory(app)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                    }
                                }.padding(.vertical, 5).tag(app.id)
                            }
                        }.listStyle(.inset)
                    }
                }.frame(minWidth: 350, idealWidth: 440)
                Group {
                    if let app = model.selectedApp {
                        RuleEditor(model: model, app: app)
                    } else {
                        ContentUnavailableView("选择一个应用", systemImage: "slider.horizontal.3",
                                               description: Text("查看占用并设置后台规则。"))
                    }
                }.frame(minWidth: 300, idealWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Text("CPU 100% 约等于一个核心满载").help("应用数值是自有进程的合计，整机 CPU 使用全部核心的口径。")
                Spacer()
                Text("每 2 秒更新").monospacedDigit()
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 10)
        }.frame(minWidth: 760, minHeight: 520)
    }
}

struct RuleEditor: View {
    @Bindable var model: AppModel
    let app: AppReading
    private var rule: AppRule { model.rules[app.id] ?? AppRule() }
    private func update(_ mutate: (inout AppRule) -> Void) {
        var changed = rule; mutate(&changed); model.setRule(app.id, rule: changed)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    AppIcon(app: app, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name).font(.title3.weight(.semibold))
                        StatusLabel(status: app.status)
                    }
                }
                HStack(spacing: 30) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("CPU").font(.caption).foregroundStyle(.secondary)
                        Text(Display.percent(app.cpuPercent)).font(.title2).monospacedDigit()
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("物理内存合计").font(.caption).foregroundStyle(.secondary)
                        Text(Display.memory(app)).font(.title2).monospacedDigit()
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("后台规则").font(.headline)
                    Picker("管理方式", selection: Binding(get: { rule.mode }, set: { mode in update { $0.mode = mode } })) {
                        ForEach(ControlMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
                    }.pickerStyle(.menu).accessibilityIdentifier("rule-mode")
                    if rule.mode == .budget {
                        HStack {
                            Text("CPU 预算")
                            Spacer()
                            Text("\(Int(rule.cpuPercent))%").monospacedDigit()
                        }
                        Slider(value: Binding(get: { rule.cpuPercent }, set: { percent in update { $0.cpuPercent = percent } }),
                               in: 5...200, step: 5).accessibilityIdentifier("cpu-budget")
                        Text("按整个应用的自有进程合计计算。").font(.caption).foregroundStyle(.secondary)
                    }
                    if rule.mode != .off {
                        HStack {
                            Text("后台等待")
                            Spacer()
                            Stepper("\(Int(rule.delaySeconds)) 秒",
                                    value: Binding(get: { rule.delaySeconds }, set: { delay in update { $0.delaySeconds = delay } }),
                                    in: 0...30, step: 1).fixedSize()
                        }
                        Text("失去前台焦点或隐藏后应用规则，切回前台恢复。").font(.caption).foregroundStyle(.secondary)
                    }
                }.disabled(!app.canControl)
                if !app.canControl {
                    Label(app.id.hasPrefix("com.apple.") ? "系统应用只用于观察。" : "当前无法读取可控进程，只显示应用信息。", systemImage: "lock").font(.callout).foregroundStyle(.secondary)
                } else if rule.mode == .gentle {
                    Text("系统忙碌时让前台应用优先获得资源。它没有固定 CPU 上限，节能效果取决于工作负载。")
                        .font(.callout).foregroundStyle(.secondary)
                } else if rule.mode == .budget {
                    Label("预算会影响音频、网络和心跳，可能造成卡顿或掉线。", systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if rule.mode != .off && app.canControl {
                    Button("移除这条规则") { model.resetRule(app.id) }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("磁盘活动").font(.headline)
                    HStack { Text("读取"); Spacer(); Text(Display.rate(app.readRate)).monospacedDigit() }
                    HStack { Text("写入"); Spacer(); Text(Display.rate(app.writeRate)).monospacedDigit() }
                }.font(.callout)
                DisclosureGroup("进程详情") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(app.id).font(.caption).textSelection(.enabled)
                        ForEach(app.samples, id: \.identity) { process in
                            HStack { Text("PID \(process.identity.pid)"); Spacer(); Text(Display.bytes(process.memoryBytes)) }
                                .font(.caption).monospacedDigit()
                        }
                    }.padding(.top, 8)
                }.foregroundStyle(.secondary)
            }.padding(24)
        }
    }
}

struct MenuPanel: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("轻程", systemImage: "leaf.fill").font(.headline)
                Spacer()
                Toggle("自动管理", isOn: Binding(get: { model.enabled }, set: { model.setEnabled($0) }))
                    .toggleStyle(.switch).controlSize(.small)
            }.padding(16)
            Divider()
            SystemStrip(reading: model.system).padding(.horizontal, -4)
            Divider()
            VStack(spacing: 10) {
                ForEach(Array(model.apps.prefix(5))) { app in
                    HStack(spacing: 9) {
                        AppIcon(app: app, size: 24)
                        Text(app.name).lineLimit(1)
                        Spacer()
                        Text(Display.percent(app.cpuPercent)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                if model.apps.isEmpty { Text("正在读取应用占用…").foregroundStyle(.secondary) }
            }.padding(16)
            Divider()
            HStack {
                Button("应用管理") { model.showManagement() }
                Spacer()
                Text("\(model.managedCount) 个生效").font(.caption).foregroundStyle(.secondary)
                Button("退出") { model.shutdown(); NSApp.terminate(nil) }
            }.padding(14)
        }.frame(width: 420).onAppear { model.refresh() }
    }
}

#Preview("应用管理") {
    ContentView(model: AppModel(preview: true))
}
#Preview("菜单栏") {
    MenuPanel(model: AppModel(preview: true))
}
