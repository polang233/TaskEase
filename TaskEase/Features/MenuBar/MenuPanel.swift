import SwiftUI
import AppKit

/// 菜单栏速览，按宿主窗口的实际可见性请求数据更新。
struct MenuPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BrandMark(size: 22)
                Text("app.name").font(.headline)
                UpdateBadge(model: model)
                Spacer()
                BackgroundControlToggle(model: model).controlSize(.small)
            }.padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 6)
            SystemStrip(reading: model.system, style: model.preferences.metricStyle).padding(.horizontal, -4)
            Divider()
            VStack(spacing: 4) {
                HStack {
                    Text("menu.topUsage").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    SortMenu(model: model)
                }.padding(.horizontal, 6).padding(.bottom, 2)
                let key = model.effectiveSortKey
                let usage = AppUsage(key, scale: model.preferences.cpuScale, apps: model.apps)
                ForEach(QuickActions.rows(model.visibleRunningApps, sortedBy: key, temporary: model.temporaryActions)) { app in
                    MenuAppRow(model: model, app: app, usage: usage)
                }
                if model.visibleRunningApps.isEmpty {
                    (model.isRefreshing ? Text("list.loading") : Text("menu.noApps"))
                        .font(.callout).foregroundStyle(.secondary)
                } else if model.savedRuleCount == 0 {
                    // 首次使用：点行即可进入规则设置。
                    Label("menu.hint.noRules", systemImage: "hand.point.up.left")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4).padding(.leading, 6)
                }
            }.padding(.horizontal, 10).padding(.vertical, 12)
            Divider()
            HStack {
                Button("menu.manageApps") { model.showManagement() }.pointingHand()
                Button("common.settings", systemImage: "gearshape") { model.showUtility(.settings) }
                    .labelStyle(.iconOnly).help("common.settings").pointingHand()
                SavingsBadge(model: model, compact: true)
                Spacer()
                Text("menu.activeCount \(model.managedCount)").font(.caption).foregroundStyle(.secondary)
                Button("common.quit") { NSApp.terminate(nil) }.pointingHand()
            }.padding(14)
        }
        .frame(width: 420)
        .background(WindowReader { [weak model] window in model?.trackMenuWindow(window) }
            .frame(width: 0, height: 0))
    }
}

/// 菜单栏中的一行应用：图标角标与状态标签说明规则是否在执行；点击打开管理窗口并选中该应用。
struct MenuAppRow: View {
    @Bindable var model: AppModel
    let app: AppReading
    let usage: AppUsage
    @State private var hovering = false

    /// 快捷操作放在行按钮之外，避免嵌套按钮吞掉点击；其余区域点击打开管理窗口。
    var body: some View {
        HStack(spacing: 9) {
            Button(action: open) {
                HStack(spacing: 9) {
                    StatusIcon(app: app, status: app.status, size: 24)
                    Text(app.name).lineLimit(1)
                    if StatusLabel.symbol(app.status) != nil {
                        StatusLabel(status: app.status).fixedSize()
                    }
                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).pointingHand()
            .help("menu.row.help")
            .accessibilityHint("menu.row.help")
            QuickActions(model: model, app: app)
            Text(usage.value(app)).monospacedDigit()
                .contentShape(Rectangle())
                .onTapGesture(perform: open)
        }
        .padding(.vertical, 5).padding(.horizontal, 6)
        .background(UsageFill(fraction: usage.fraction(app)))
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.primary.opacity(hovering ? 0.07 : 0)))
        .onHover { hovering = $0 }
    }

    /// 已配置列表里找不到该应用时切回运行列表，再选中它。
    private func open() {
        if !model.filteredApps.contains(where: { $0.id == app.id }) { model.setApplicationList(.running) }
        model.search = ""
        model.selectedID = app.id
        model.showManagement()
    }
}

#Preview("菜单栏") {
    MenuPanel(model: AppModel(preview: true))
}
