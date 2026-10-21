import SwiftUI
import AppKit

/// 显示版本、版权与许可信息，提供帮助和许可证入口。
struct AboutView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit()
                .frame(width: 80, height: 80).accessibilityHidden(true)
            Text("about.title").font(.title2.weight(.semibold))
            Text("about.version \(AppVersion.short) \(AppVersion.build)").font(.caption).foregroundStyle(.secondary)
            Text("about.tagline")
                .font(.callout).multilineTextAlignment(.center)
            Link("about.star", destination: ProjectLinks.repository)
                .font(.callout).multilineTextAlignment(.center).pointingHand()
            updateStatus
            Divider().padding(.vertical, 4)
            HStack(spacing: 16) {
                Button("common.help") { model.showUtility(.help) }
                Button("about.license") { model.showUtility(.license) }
                Link("about.feedback", destination: ProjectLinks.issues).accessibilityIdentifier("project-issues")
                Button("window.statistics") { model.showUtility(.statistics) }
                    .accessibilityIdentifier("open-usage-statistics")
            }
            .buttonStyle(.bordered)
            Text(verbatim: "© \(String(Calendar.current.component(.year, from: Date()))) Polang233 · GPL-3.0")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 版本号旁的检查按钮与结果；有新版本时打开更新窗口。
    @ViewBuilder private var updateStatus: some View {
        HStack(spacing: 8) {
            switch model.updates.phase {
            case .checking:
                ProgressView().controlSize(.small)
                Text("update.checking").foregroundStyle(.secondary)
            case .upToDate:
                Label("update.upToDate", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            case .noRelease:
                Text("update.noRelease").foregroundStyle(.secondary)
            case .failed(let message):
                Text(message).foregroundStyle(.secondary)
            case .available, .downloading, .installing, .installFailed:
                if let release = model.updates.release {
                    Label("update.available \(release.version)", systemImage: "arrow.down.circle").foregroundStyle(.tint)
                    Button("update.view") { model.showUtility(.update) }
                        .buttonStyle(.link).pointingHand()
                }
            case .idle:
                EmptyView()
            }
            if !model.updates.isBusy && !model.updates.hasUpdate {
                Button("update.check") { model.updates.check() }
                    .buttonStyle(.link).pointingHand()
                    .accessibilityIdentifier("check-updates")
            }
        }.font(.caption)
    }
}

#Preview("关于") {
    AboutView(model: AppModel(preview: true)).frame(width: 580, height: 430)
}
