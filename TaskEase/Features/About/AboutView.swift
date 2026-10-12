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
            Link("软件好用吗？软件开源在 GitHub，欢迎给这个项目点个 Star 🌟", destination: ProjectLinks.repository)
                .font(.callout).multilineTextAlignment(.center).pointingHand()
            updateStatus
            Divider().padding(.vertical, 4)
            HStack(spacing: 16) {
                Button("使用帮助") { model.showUtility(.help) }
                Button("许可证") { model.showUtility(.license) }
                Link("问题反馈", destination: ProjectLinks.issues).accessibilityIdentifier("project-issues")
                Button("使用统计") { model.showUtility(.statistics) }
                    .accessibilityIdentifier("open-usage-statistics")
            }
            .buttonStyle(.bordered)
            Text("© \(String(Calendar.current.component(.year, from: Date()))) Polang233 · GPL-3.0")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 版本号旁的检查按钮与结果，只在点击时联网。
    @ViewBuilder private var updateStatus: some View {
        HStack(spacing: 8) {
            switch model.updates.state {
            case .checking:
                ProgressView().controlSize(.small)
                Text("正在检查更新…").foregroundStyle(.secondary)
            case .upToDate:
                Label("已是最新版本", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            case .noRelease:
                Text("还没有发布版本").foregroundStyle(.secondary)
            case .failed(let message):
                Text(message).foregroundStyle(.secondary)
            case .available(let version, let url):
                Label("发现新版本 \(version)", systemImage: "arrow.down.circle").foregroundStyle(.tint)
                Link("前往下载", destination: url).pointingHand()
            case .idle:
                EmptyView()
            }
            if model.updates.state != .checking {
                Button("检查更新") { model.updates.check() }
                    .buttonStyle(.link).pointingHand()
                    .accessibilityIdentifier("check-updates")
            }
        }.font(.caption)
    }
}

#Preview("关于") {
    AboutView(model: AppModel(preview: true)).frame(width: 580, height: 430)
}
