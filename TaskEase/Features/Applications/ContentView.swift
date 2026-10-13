import SwiftUI

/// 管理窗口，展示运行中的应用、已配置规则与当前选中的规则编辑器。
struct ContentView: View {
    @Bindable var model: AppModel
    /// 管理窗口把页眉放进透明标题栏；独立预览为 nil，保持普通页眉。
    var titlebar: TitlebarMetrics?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    BrandMark(size: 24)
                    Text("app.name").font(.title3.weight(.semibold))
                    Text("header.version \(AppVersion.short)").font(.caption).foregroundStyle(.secondary)
                        .padding(.top, 2)
                }.modifier(WindowHeaderDrag(enabled: titlebar != nil))
                // 放在拖动区之外，避免点击被窗口拖动层拦截。
                UpdateBadge(model: model)
                Color.clear.frame(maxWidth: .infinity).frame(height: 32)
                    .modifier(WindowHeaderDrag(enabled: titlebar != nil))
                if model.managedCount > 0 {
                    Text("header.activeLimits \(model.managedCount)").font(.callout).foregroundStyle(.secondary)
                }
                BackgroundControlToggle(model: model)
                Button("common.settings", systemImage: "gearshape") { model.showUtility(.settings) }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).font(.title3)
                    .help("common.settings").pointingHand().accessibilityIdentifier("open-settings")
            }.padding(.leading, titlebar.map { $0.leading + 16 } ?? 20)
                .padding(.trailing, 20).padding(.vertical, titlebar == nil ? 14 : 0)
                .frame(height: titlebar?.height)
            Divider()
            SystemStrip(reading: model.system, isPaused: model.managementDisplayPaused, style: model.preferences.metricStyle)
            Divider()
            if let error = model.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(error).font(.callout)
                    Spacer()
                    Button("error.recoverRetry") { model.setEnabled(true) }.disabled(!model.canEnable)
                }.padding(12).background(Color.orange.opacity(0.08))
            }
            HSplitView {
                applicationList.frame(minWidth: 340, idealWidth: 400)
                Group {
                    if let app = model.selectedApp {
                        RuleEditor(model: model, app: app)
                    } else {
                        ContentUnavailableView("empty.selectApp.title", systemImage: "slider.horizontal.3",
                                               description: Text("empty.selectApp.message"))
                    }
                }.frame(minWidth: 360, idealWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
            }

        }
        .frame(minWidth: 840, minHeight: 580)
        .ignoresSafeArea(.container, edges: titlebar == nil ? [] : .top)
        .onChange(of: model.search) { _, _ in model.ensureSelection() }
    }

    private var applicationList: some View {
        VStack(spacing: 0) {
            // 宽度足够时列表切换与排序菜单同一行，窄时排序菜单换到下一行。
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { listPicker; Spacer(minLength: 0); SortMenu(model: model, showsSystemToggle: true) }
                VStack(alignment: .trailing, spacing: 8) { listPicker; SortMenu(model: model, showsSystemToggle: true) }
            }.padding(.horizontal, 16).padding(.top, 14)
            searchField.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 10)
            Divider()
            if model.filteredApps.isEmpty {
                emptyList.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $model.selectedID) {
                    let key = model.effectiveSortKey
                    let usage = AppUsage(key, scale: model.preferences.cpuScale, apps: model.apps)
                    ForEach(model.filteredApps) { app in
                        HStack(spacing: 10) {
                            AppIcon(app: app, size: 30)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(app.name).lineLimit(1)
                                HStack(spacing: 7) {
                                    StatusLabel(status: app.status)
                                    if app.isRunning && !app.targets.isEmpty {
                                        Text("list.processes \(app.targets.count)").font(.caption).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            Spacer()
                            if app.isRunning {
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(usage.value(app)).monospacedDigit()
                                    Text(usage.secondary(app))
                                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                    if model.preferences.networkActivityVisible && key != .network {
                                        Text("↓ " + Display.networkRate(app.network?.receiveRate) +
                                             "  ↑ " + Display.networkRate(app.network?.sendRate))
                                            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8).padding(.horizontal, 8)
                        .background(UsageFill(fraction: usage.fraction(app)))
                        .contentShape(Rectangle()).pointingHand()
                        .listRowSeparator(.visible)
                        .tag(app.id)
                    }
                }.listStyle(.inset)
            }
        }
    }

    private var listPicker: some View {
        Picker("list.picker", selection: Binding(get: { model.applicationList }, set: { model.setApplicationList($0) })) {
            ForEach(ApplicationList.allCases, id: \.self) { Text($0.title).tag($0) }
        }.selectionRail().labelsHidden().fixedSize()
            .accessibilityIdentifier("application-list")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("list.search \(model.filteredApps.count)", text: $model.search).textFieldStyle(.plain)
                .focused($searchFocused)
                .accessibilityIdentifier("app-search")
            if !model.search.isEmpty {
                Button("list.clearSearch", systemImage: "xmark.circle.fill") { model.search = "" }
                    .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary).pointingHand()
            }
        }
        .padding(.horizontal, 9).frame(height: 30)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(searchFocused ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { searchFocused = true }
    }

    @ViewBuilder private var emptyList: some View {
        if model.applicationList == .configured && model.savedRuleCount == 0 {
            ContentUnavailableView {
                Label("empty.noRules.title", systemImage: "slider.horizontal.3")
            } description: {
                Text("empty.noRules.message")
            } actions: {
                Button("empty.noRules.action") { model.setApplicationList(.running) }
            }
        } else if model.isRefreshing && model.apps.isEmpty {
            ProgressView("list.loading")
        } else {
            ContentUnavailableView("empty.noMatch.title", systemImage: "magnifyingglass",
                                   description: Text("empty.noMatch.message"))
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

#Preview("网络规则") {
    let model = AppModel(preview: true)
    var app = AppModel.exampleApps[1]
    app.network = NetworkReading(receiveRate: 128 * 1024, sendRate: 24 * 1024, sampledProcesses: 2)
    model.apply(MonitoringSnapshot(apps: [app], system: model.system, networkStatus: .available))
    model.setNetworkRule(app.id, rule: NetworkRule(mode: .limit, scope: .always))
    model.setApplicationList(.configured)
    return ContentView(model: model)
}

#Preview("深色") {
    let model = AppModel(preview: true)
    model.updatePreferences { $0.theme = .dark }
    return ContentView(model: model)
}

/// 透明标题栏的实测尺寸：页眉与标题栏同高，红绿灯和品牌标识共用一条竖直中线。
struct TitlebarMetrics: Equatable {
    var height: CGFloat
    /// 红绿灯右边缘距窗口左侧的距离。
    var leading: CGFloat

    /// 以红绿灯中心为准：页眉高度取其到顶边距离的两倍，不依赖各系统版本的工具栏高度。
    @MainActor static func measure(_ window: NSWindow) -> TitlebarMetrics {
        guard let close = window.standardWindowButton(.closeButton), let bar = close.superview,
              let zoom = window.standardWindowButton(.zoomButton) else {
            return TitlebarMetrics(height: 52, leading: 68)
        }
        let center = bar.isFlipped ? close.frame.midY : bar.bounds.height - close.frame.midY
        return TitlebarMetrics(height: max(2 * center, 44), leading: zoom.frame.maxX)
    }
}
