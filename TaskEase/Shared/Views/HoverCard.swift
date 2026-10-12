import AppKit
import SwiftUI

/// 无箭头卡片：不抢焦点的子面板，放在锚点下方并限制在屏幕内；关闭时释放窗口、视图和回调。
@MainActor
final class HoverCardController {
    private var panel: NSPanel?
    private var hosting: NSHostingController<CardSurface>?
    private weak var anchor: NSView?
    private weak var parent: NSWindow?
    private var hover: ((Bool) -> Void)?
    var isOpen: Bool { panel != nil }

    @discardableResult
    func present(anchor: NSView, content: AnyView, hover: @escaping (Bool) -> Void) -> Bool {
        close()
        guard let parent = anchor.window else { return false }
        self.anchor = anchor
        self.parent = parent
        self.hover = hover
        let panel = CardPanel(contentRect: NSRect(x: 0, y: 0, width: 224, height: 120),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        panel.appearance = anchor.effectiveAppearance
        let hosting = NSHostingController(rootView: surface(content))
        hosting.sizingOptions = []
        // 非激活面板不会成为主窗口，SwiftUI 的 onHover 可能收不到事件；改用始终生效的跟踪区域。
        let container = HoverTrackingView { [weak self] inside in self?.hover?(inside) }
        hosting.view.frame = container.bounds
        hosting.view.autoresizingMask = [.width, .height]
        container.addSubview(hosting.view)
        panel.contentView = container
        self.panel = panel
        self.hosting = hosting
        parent.addChildWindow(panel, ordered: .above)
        place(size: hosting.view.fittingSize)
        panel.orderFront(nil)
        return true
    }

    func update(content: AnyView) {
        guard panel != nil else { return }
        hosting?.rootView = surface(content)
    }

    private func surface(_ content: AnyView) -> CardSurface {
        CardSurface(content: content, resize: { [weak self] size in self?.place(size: size) })
    }

    /// 卡片与锚点间只留 4 点空隙，指针移入时几乎不会离开两者。
    private func place(size: NSSize) {
        guard size.width > 0, size.height > 0, let panel, let anchor, let parent else { return }
        let source = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let screen = parent.screen?.visibleFrame ?? source.insetBy(dx: -500, dy: -500)
        let x = min(max(source.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        var y = source.minY - size.height - 4
        if y < screen.minY + 8 { y = source.maxY + 4 }
        y = min(max(y, screen.minY + 8), screen.maxY - size.height - 8)
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
    }

    func close() {
        if let panel {
            parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            panel.contentView = nil
            panel.close()
        }
        panel = nil
        hosting = nil
        hover = nil
        anchor = nil
        parent = nil
    }
}

/// 统一处理锚点与卡片的悬停：两者都离开后短暂宽限再关闭，不使用全局鼠标监听或周期定时器。
@MainActor
final class HoverCardCoordinator {
    private let controller = HoverCardController()
    private var anchorInside = false
    private var cardInside = false
    private var dismissTask: Task<Void, Never>?
    var onClose: (() -> Void)?
    var isOpen: Bool { controller.isOpen }

    func show(anchor: NSView, content: AnyView) {
        dismissTask?.cancel()
        cardInside = false
        controller.present(anchor: anchor, content: content) { [weak self] inside in
            self?.cardInside = inside
            self?.scheduleDismissal()
        }
    }

    func update(content: AnyView) { controller.update(content: content) }

    func anchorHover(_ inside: Bool) {
        anchorInside = inside
        scheduleDismissal()
    }

    private func scheduleDismissal() {
        dismissTask?.cancel()
        guard controller.isOpen, !anchorInside, !cardInside else { return }
        dismissTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(90)) } catch { return }
            guard let self, !self.anchorInside, !self.cardInside else { return }
            self.close()
        }
    }

    func close() {
        dismissTask?.cancel()
        dismissTask = nil
        cardInside = false
        let wasOpen = controller.isOpen
        controller.close()
        if wasOpen { onClose?() }
    }
}

private final class CardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 圆角雾面卡片，尺寸跟随内容。
private struct CardSurface: View {
    let content: AnyView
    let resize: (CGSize) -> Void

    var body: some View {
        content
            .fixedSize(horizontal: true, vertical: true)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.08), lineWidth: 0.5))
            .padding(2)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { resize($0) }
    }
}

/// `.activeAlways` 让应用不在前台或面板非 key 时也能收到进出事件。
private final class HoverTrackingView: NSView {
    private let changed: (Bool) -> Void

    init(changed: @escaping (Bool) -> Void) {
        self.changed = changed
        super.init(frame: NSRect(x: 0, y: 0, width: 224, height: 120))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseEntered(with event: NSEvent) { changed(true) }
    override func mouseExited(with event: NSEvent) { changed(false) }
}

/// 只保留锚点视图的弱引用，供面板定位，避免 SwiftUI 状态与 AppKit 视图相互持有。
final class WeakAnchor {
    weak var view: NSView?
    init(_ view: NSView) { self.view = view }
}

/// 在 SwiftUI 视图背后放一个不接收点击的 NSView，作为卡片定位锚点。
struct AnchorReader: NSViewRepresentable {
    let attached: @MainActor (NSView) -> Void

    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        view.attached = attached
        return view
    }
    func updateNSView(_ nsView: Probe, context: Context) { nsView.attached = attached }

    final class Probe: NSView {
        var attached: @MainActor (NSView) -> Void = { _ in }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            Task { @MainActor [weak self] in
                guard let self, window != nil else { return }
                attached(self)
            }
        }
    }
}
