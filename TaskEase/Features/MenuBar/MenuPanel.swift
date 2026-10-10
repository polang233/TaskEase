import SwiftUI
import AppKit

/// 菜单栏速览，按宿主窗口的实际可见性请求数据更新。
struct MenuPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BrandMark(size: 22)
                Text("轻程").font(.headline)
                Spacer()
                BackgroundControlToggle(model: model).controlSize(.small)
            }.padding(16)
            Divider()
            SystemStrip(reading: model.system).padding(.horizontal, -4)
            Divider()
            VStack(spacing: 12) {
                ForEach(Array(model.visibleRunningApps.prefix(5))) { app in
                    HStack(spacing: 9) {
                        AppIcon(app: app, size: 24)
                        Text(app.name).lineLimit(1)
                        Spacer()
                        Text(Display.percent(app.cpuPercent)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                if model.visibleRunningApps.isEmpty {
                    Text(model.isRefreshing ? "正在读取应用占用…" : "当前没有可显示的应用")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }.padding(16)
            Divider()
            HStack {
                Button("应用管理") { model.showManagement() }
                Button("设置", systemImage: "gearshape") { model.showUtility(.settings) }
                    .labelStyle(.iconOnly).help("设置")
                Spacer()
                Text("\(model.managedCount) 个生效").font(.caption).foregroundStyle(.secondary)
                Button("退出") { NSApp.terminate(nil) }
            }.padding(14)
        }
        .frame(width: 420)
        .preferredColorScheme(model.preferences.theme.colorScheme)
        .background(WindowReader { [weak model] window in model?.trackMenuWindow(window) }
            .frame(width: 0, height: 0))
    }
}

#Preview("菜单栏") {
    MenuPanel(model: AppModel(preview: true))
}
