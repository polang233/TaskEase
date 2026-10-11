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
            HStack(spacing: 14) {
                Text("版本 \(AppVersion.short) · 构建 \(AppVersion.build)")
                Text("macOS 14+ · Apple Silicon")
            }.font(.caption).foregroundStyle(.secondary)
            Text("查看应用占用，按前后台状态限制 CPU 资源。")
                .font(.callout).multilineTextAlignment(.center)
            VStack(spacing: 6) {
                Link("免费且开源于 GitHub", destination: ProjectLinks.repository)
                Link("觉得好用，欢迎给项目点 Star 🌟", destination: ProjectLinks.repository)
            }.font(.callout)
            Divider().padding(.vertical, 4)
            HStack(spacing: 16) {
                Button("使用帮助") { model.showUtility(.help) }
                Button("许可证") { model.showUtility(.license) }
                Link("问题反馈", destination: ProjectLinks.issues).accessibilityIdentifier("project-issues")
                Button("使用统计") { model.showUtility(.statistics) }
                    .accessibilityIdentifier("open-usage-statistics")
            }
            .buttonStyle(.bordered)
            Text("© \(String(Calendar.current.component(.year, from: Date()))) Polang · GPL-3.0")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("关于") {
    AboutView(model: AppModel(preview: true)).frame(width: 580, height: 430)
}
