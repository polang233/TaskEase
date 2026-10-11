import SwiftUI
import AppKit

/// 界面共用的品牌标记，尺寸以逻辑点计。
struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        Image("TaskEaseMark").resizable().scaledToFit()
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}
@MainActor
private enum ApplicationIcons {
    static var images: [String: NSImage] = [:]

    static func image(at path: String) -> NSImage {
        if let cached = images[path] { return cached }
        if images.count > 128 { images.removeAll() }
        let image = NSWorkspace.shared.icon(forFile: path)
        images[path] = image
        return image
    }
}

struct AppIcon: View {
    let app: AppReading
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let path = app.bundlePaths.first {
                Image(nsImage: ApplicationIcons.image(at: path)).resizable()
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
        case .gentle, .budget: .green
        case .waiting: .orange
        default: .secondary
        }
    }

    var body: some View {
        Text(status.title).font(.caption).foregroundStyle(color)
    }
}

/// 总开关的无规则提示仅在点击时展示，保持主界面紧凑。
struct BackgroundControlToggle: View {
    @Bindable var model: AppModel
    @State private var showHint = false

    var body: some View {
        Toggle("启用后台限制", isOn: Binding(get: { model.enabled }, set: { model.setEnabled($0) }))
            .toggleStyle(.switch)
            .disabled(!model.canEnable)
            .accessibilityIdentifier("management-toggle")
            .overlay {
                if !model.canEnable {
                    Button { showHint = true } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("启用后台限制的配置提示")
                    .accessibilityIdentifier("management-unavailable")
                }
            }
            .popover(isPresented: $showHint, arrowEdge: .bottom) {
                Text("先为应用设置后台规则")
                    .font(.callout).padding(16)
                    .accessibilityIdentifier("configure-rules-hint")
            }
            .onChange(of: model.canEnable) { _, ready in
                if ready { showHint = false }
            }
    }
}
