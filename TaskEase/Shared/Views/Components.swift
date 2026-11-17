import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 界面共用的品牌标记，尺寸以逻辑点计。
struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        Image("TaskEaseMark").resizable().scaledToFit()
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}
/// 应用图标缩成一张 96 像素位图后缓存，不保留系统图标的多尺寸表示。
@MainActor
private enum ApplicationIcons {
    static let pixels = 96
    static var images: [String: NSImage] = [:]

    /// 没有应用包路径时使用系统通用应用图标，与访达中的外观一致。
    static let generic: NSImage = {
        let source = NSWorkspace.shared.icon(for: .applicationBundle)
        return downscaled(source) ?? source
    }()

    static func image(at path: String) -> NSImage {
        if let cached = images[path] { return cached }
        if images.count > 128 { images.removeAll() }
        let source = NSWorkspace.shared.icon(forFile: path)
        let image = downscaled(source) ?? source
        images[path] = image
        return image
    }

    private static func downscaled(_ source: NSImage) -> NSImage? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: pixels / 2, height: pixels / 2))
        image.addRepresentation(bitmap)
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
                Image(nsImage: ApplicationIcons.generic).resizable()
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// 规则生效相关的状态用浅色胶囊标签突出，其余状态保持次要文字。
struct StatusLabel: View {
    let status: RuleStatus

    static func tint(_ status: RuleStatus) -> Color? {
        switch status {
        case .gentle, .budget: .green
        case .muted, .quieted: .indigo
        case .suspended, .held: .blue
        case .released: .orange
        case .waiting: .orange
        default: nil
        }
    }

    /// 图标角标使用的系统符号；没有规则或无法控制的应用不显示角标。
    static func symbol(_ status: RuleStatus) -> String? {
        switch status {
        case .budget: "gauge.with.dots.needle.33percent"
        case .gentle: "tortoise.fill"
        case .suspended: "pause.fill"
        case .held: "pause.circle.fill"
        case .released: "play.fill"
        case .muted: "speaker.slash.fill"
        case .quieted: "speaker.wave.1.fill"
        case .waiting: "clock.fill"
        case .foreground: "macwindow"
        case .paused: "power"
        default: nil
        }
    }

    var body: some View {
        if let tint = Self.tint(status) {
            Text(status.title).font(.caption2.weight(.semibold)).foregroundStyle(tint)
                .padding(.horizontal, 6).padding(.vertical, 1.5)
                .background(tint.opacity(0.13), in: Capsule())
        } else {
            Text(status.title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// 应用图标加右下角规则状态角标：生效时用状态色，规则就绪但未执行（前台、总开关关闭）时为灰色。
/// 角标只是视觉提示，状态文字由同一行的 StatusLabel 朗读。
struct StatusIcon: View {
    let app: AppReading
    let status: RuleStatus
    var size: CGFloat = 30

    var body: some View {
        AppIcon(app: app, size: size).overlay(alignment: .bottomTrailing) {
            if let symbol = StatusLabel.symbol(status) {
                let badge = max(12, size * 0.46)
                Image(systemName: symbol)
                    .font(.system(size: badge * 0.52, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: badge, height: badge)
                    .background(Circle().fill(StatusLabel.tint(status) ?? Color.gray))
                    .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                    .offset(x: badge * 0.22, y: badge * 0.22)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// 详情区的分组卡片，与设置窗口的分组表单观感一致：浅底色、细描边、可选小标题。
struct SectionCard<Content: View>: View {
    var title: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
    }
}

/// 有新版本时显示的蓝色胶囊；指针移上去稍微放大，点击打开更新窗口。没有新版本时不占位。
struct UpdateBadge: View {
    @Bindable var model: AppModel
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if model.updates.showsBadge, let release = model.updates.release {
            Button { model.showUtility(.update) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("update.badge \(release.version)")
                }
                .font(.caption.weight(.semibold)).lineLimit(1).fixedSize()
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Color.accentColor.opacity(hovering ? 0.22 : 0.15), in: Capsule())
                .foregroundStyle(Color.accentColor)
                .scaleEffect(hovering ? 1.08 : 1)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain).pointingHand()
            .onHover { inside in
                if reduceMotion { hovering = inside }
                else { withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { hovering = inside } }
            }
            .accessibilityHint("update.badge.hint").accessibilityIdentifier("update-badge")
        }
    }
}

/// 总开关在没有规则时置灰；点击后用无箭头卡片提示，指针离开开关和卡片即关闭。
struct BackgroundControlToggle: View {
    @Bindable var model: AppModel
    @State private var hint = HoverCardCoordinator()
    @State private var anchor: WeakAnchor?

    var body: some View {
        Toggle("toggle.enable", isOn: Binding(get: { model.enabled }, set: { model.setEnabled($0) }))
            .toggleStyle(.switch).lineLimit(1).fixedSize()
            .disabled(!model.canEnable)
            .accessibilityIdentifier("management-toggle")
            .background(AnchorReader { view in
                if anchor?.view !== view { anchor = WeakAnchor(view) }
            })
            .overlay {
                if !model.canEnable {
                    Button { showHint() } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).pointingHand()
                    .accessibilityLabel("toggle.enable.hint.a11y")
                    .accessibilityIdentifier("management-unavailable")
                    .onHover { hint.anchorHover($0) }
                }
            }
            .onChange(of: model.canEnable) { _, ready in
                if ready { hint.close() }
            }
            .onDisappear { hint.close() }
    }

    private func showHint() {
        guard let view = anchor?.view else { return }
        hint.show(anchor: view, content: AnyView(
            Text("toggle.enable.hint").font(.callout).padding(.horizontal, 14).padding(.vertical, 10)
                .accessibilityIdentifier("configure-rules-hint")))
        hint.anchorHover(true)
    }
}
