import SwiftUI
import AppKit

/// 显示版本、版权与许可信息，提供帮助和许可证入口。
struct AboutView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit()
                .frame(width: 80, height: 80).accessibilityHidden(true)
            Text("TaskEase · 轻程").font(.title2.weight(.semibold))
            Text("版本 \(AppVersion.short) · 构建 \(AppVersion.build)").font(.callout).foregroundStyle(.secondary)
            Text("查看应用占用，按前后台状态限制 CPU 资源。")
                .font(.callout).multilineTextAlignment(.center)
            Text("Apple Silicon · macOS 14+").font(.caption).foregroundStyle(.secondary)
            Text("本软件按 GNU GPLv3 分发，无任何担保。你可以依照许可证修改和再分发。")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Divider().padding(.vertical, 4)
            HStack(spacing: 16) {
                Button("使用帮助") { model.showUtility(.help) }
                Button("许可证") { model.showUtility(.license) }
                Button("后台规则") {
                    model.setApplicationList(.configured)
                    model.showManagement()
                }
            }
            Divider().padding(.vertical, 4)
            Toggle("匿名使用统计", isOn: Binding(get: { model.usageAnalytics.enabled },
                set: { model.usageAnalytics.setEnabled($0) }))
                .toggleStyle(.checkbox).accessibilityIdentifier("usage-analytics-toggle")
                .disabled(!model.usageAnalytics.isConfigured)
            Text("匿名上传使用概况，不包含个人信息或其他应用明细。")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("© \(String(Calendar.current.component(.year, from: Date()))) Polang · GPL-3.0")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("关于") {
    AboutView(model: AppModel(preview: true)).frame(width: 580, height: 620)
}
