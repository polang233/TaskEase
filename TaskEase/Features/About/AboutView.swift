import SwiftUI
import AppKit

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
            Text("Apple Silicon · macOS 27+").font(.caption).foregroundStyle(.secondary)
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
            Text("© \(String(Calendar.current.component(.year, from: Date()))) Polang · GPL-3.0")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("关于") {
    AboutView(model: AppModel(preview: true)).frame(width: 440, height: 440)
}
