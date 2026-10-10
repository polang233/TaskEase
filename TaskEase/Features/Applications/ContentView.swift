import SwiftUI

/// 管理窗口，展示运行中的应用、已配置规则与当前选中的规则编辑器。
struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BrandMark(size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text("轻程").font(.title2.weight(.semibold))
                    Text("TaskEase · \(AppVersion.short)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.managedCount > 0 {
                    Text("\(model.managedCount) 个应用限制生效").font(.callout).foregroundStyle(.secondary)
                }
                BackgroundControlToggle(model: model)
                Button("设置", systemImage: "gearshape") { model.showUtility(.settings) }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).font(.title3)
                    .help("设置").accessibilityIdentifier("open-settings")
            }.padding(20)
            Divider()
            SystemStrip(reading: model.system)
            Divider()
            if let error = model.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(error).font(.callout)
                    Spacer()
                    Button("恢复并重试") { model.setEnabled(true) }.disabled(!model.canEnable)
                }.padding(12).background(Color.orange.opacity(0.08))
            }
            HSplitView {
                applicationList.frame(minWidth: 340, idealWidth: 400)
                Group {
                    if let app = model.selectedApp {
                        RuleEditor(model: model, app: app)
                    } else {
                        ContentUnavailableView("选择一个应用", systemImage: "slider.horizontal.3",
                                               description: Text("查看占用并设置后台规则。"))
                    }
                }.frame(minWidth: 360, idealWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
            }

        }
        .frame(minWidth: 840, minHeight: 580)
        .preferredColorScheme(model.preferences.theme.colorScheme)
        .onChange(of: model.search) { _, _ in model.ensureSelection() }
    }

    private var applicationList: some View {
        VStack(spacing: 0) {
            Picker("应用列表", selection: Binding(get: { model.applicationList }, set: { model.setApplicationList($0) })) {
                ForEach(ApplicationList.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 16).padding(.top, 14)
                .accessibilityIdentifier("application-list")
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索应用", text: $model.search).textFieldStyle(.plain)
                    .accessibilityIdentifier("app-search")
                if !model.search.isEmpty {
                    Button("清除搜索", systemImage: "xmark.circle.fill") { model.search = "" }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 18).padding(.vertical, 12)
            HStack {
                Text("\(model.filteredApps.count) 个应用").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.applicationList == .running {
                    Toggle("显示系统应用", isOn: Binding(get: { model.preferences.showSystemApps },
                                                   set: { value in model.updatePreferences { $0.showSystemApps = value } }))
                        .toggleStyle(.checkbox).font(.caption)
                        .accessibilityIdentifier("show-system-apps")
                }
            }.padding(.horizontal, 18).padding(.bottom, 12)
            Divider()
            if model.filteredApps.isEmpty {
                emptyList.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $model.selectedID) {
                    ForEach(model.filteredApps) { app in
                        HStack(spacing: 10) {
                            AppIcon(app: app, size: 30)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(app.name).lineLimit(1)
                                HStack(spacing: 7) {
                                    StatusLabel(status: app.status)
                                    if app.isRunning && !app.targets.isEmpty {
                                        Text("\(app.targets.count) 个进程").font(.caption).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            Spacer()
                            if app.isRunning {
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(Display.percent(app.cpuPercent)).monospacedDigit()
                                    Text(Display.memory(app)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                        }.padding(.vertical, 6).tag(app.id)
                    }
                }.listStyle(.inset)
            }
        }
    }

    @ViewBuilder private var emptyList: some View {
        if model.applicationList == .configured && model.rules.isEmpty {
            ContentUnavailableView {
                Label("还没有后台规则", systemImage: "slider.horizontal.3")
            } description: {
                Text("选择一个运行中的应用，为它开启后台限制。")
            } actions: {
                Button("选择应用") { model.setApplicationList(.running) }
            }
        } else if model.isRefreshing && model.apps.isEmpty {
            ProgressView("正在读取应用占用…")
        } else {
            ContentUnavailableView("没有匹配的应用", systemImage: "magnifyingglass",
                                   description: Text("调整搜索条件或应用显示设置。"))
        }
    }
}

#Preview("应用管理") {
    ContentView(model: AppModel(preview: true))
}

#Preview("已配置规则") {
    let model = AppModel(preview: true)
    model.setRule("example.browser", rule: AppRule(mode: .budget, cpuPercent: 20, delaySeconds: 3))
    model.setEnabled(true)
    model.setApplicationList(.configured)
    return ContentView(model: model)
}

#Preview("深色") {
    let model = AppModel(preview: true)
    model.updatePreferences { $0.theme = .dark }
    return ContentView(model: model)
}
