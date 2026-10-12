import AppKit
import SwiftUI

/// 无箭头卡片：不抢焦点的子面板，放在锚点下方并限制在屏幕内；关闭时淡出后释放窗口、视图和回调。
/// 卡片打开或正在淡出时切换锚点，沿用同一面板滑到新位置并交叉淡入内容，形成连续的一张卡片。
@MainActor
final class HoverCardController {
    private var panel: NSPanel?
    private var hosting: NSHostingController<CardSurface>?
    private weak var anchor: NSView?
    private weak var parent: NSWindow?
    private var hover: ((Bool) -> Void)?
    private var key: AnyHashable = 0
    /// 面板已按锚点定位并显示，之后的位置与尺寸变化才走动画。
    private var placed = false
    /// 关闭后仍在淡出的面板；淡出期间重新打开时直接接回。
    private var fading: (panel: NSPanel, hosting: NSHostingController<CardSurface>?, parent: NSWindow?, generation: Int)?
    private var generation = 0
    var isOpen: Bool { panel != nil }

    private static let moveDuration = 0.22
    private static let fadeDuration = 0.14

    @discardableResult
    func present(anchor: NSView, content: AnyView, key: AnyHashable, hover: @escaping (Bool) -> Void) -> Bool {
        guard let parent = anchor.window else { close(); return false }
        if panel != nil, self.parent === parent {
            retarget(anchor: anchor, content: content, key: key, hover: hover)
            return true
        }
        if panel == nil, let fading, fading.parent === parent, fading.hosting != nil {
            // 接回淡出中的面板：取消释放，恢复不透明并移动到新锚点；面板淡出期间仍是子窗口。
            self.fading = nil
            panel = fading.panel
            hosting = fading.hosting
            self.parent = parent
            placed = true
            fading.panel.ignoresMouseEvents = false
            retarget(anchor: anchor, content: content, key: key, hover: hover)
            animate(Self.fadeDuration) { fading.panel.animator().alphaValue = 1 }
            return true
        }
        close(animated: false)
        self.anchor = anchor
        self.parent = parent
        self.hover = hover
        self.key = key
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
        panel.alphaValue = 0
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
        placed = false
        // 首次定位前不显示：此时内容尺寸可能还未算出，面板仍在屏幕原点，直接显示会从左下角滑入。
        place(size: hosting.view.fittingSize)
        return true
    }

    func update(content: AnyView) {
        guard panel != nil else { return }
        hosting?.rootView = surface(content)
    }

    private func retarget(anchor: NSView, content: AnyView, key: AnyHashable, hover: @escaping (Bool) -> Void) {
        self.anchor = anchor
        self.hover = hover
        self.key = key
        hosting?.rootView = surface(content)
        // 内容尺寸未变时不会触发几何回调，这里按当前尺寸先移到新锚点。
        if let size = panel?.frame.size { place(size: size) }
    }

    private func surface(_ content: AnyView) -> CardSurface {
        CardSurface(content: content, key: key, resize: { [weak self] size in self?.place(size: size) })
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
        let frame = NSRect(origin: NSPoint(x: x, y: y), size: size).integral
        if !placed {
            panel.setFrame(frame, display: false)
            placed = true
            parent.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
            animate(Self.fadeDuration) { panel.animator().alphaValue = 1 }
            return
        }
        guard frame != panel.frame else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(frame, display: true)
        } else {
            animate(Self.moveDuration) { panel.animator().setFrame(frame, display: true) }
        }
    }

    /// 点击发生在当前卡片或锚点上，用于固定卡片时判断是否点到了别处。
    func contains(_ event: NSEvent) -> Bool {
        guard let panel, let window = event.window else { return false }
        if window === panel { return true }
        guard window === parent, let anchor else { return false }
        return anchor.convert(anchor.bounds, to: nil).contains(event.locationInWindow)
    }

    var parentWindow: NSWindow? { parent }

    func close(animated: Bool = true) {
        if let fading, !animated || fading.panel !== panel {
            discard(fading.panel, parent: fading.parent)
            self.fading = nil
        }
        if let panel {
            if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                generation += 1
                let current = generation
                fading = (panel, hosting, parent, current)
                // 淡出中的面板不再拦截指针，避免挡住下方的指标。
                panel.ignoresMouseEvents = true
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Self.fadeDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.animator().alphaValue = 0
                } completionHandler: { [weak self] in
                    Task { @MainActor in self?.finishFade(current) }
                }
            } else {
                discard(panel, parent: parent)
            }
        }
        panel = nil
        hosting = nil
        hover = nil
        anchor = nil
        parent = nil
        placed = false
    }

    private func finishFade(_ current: Int) {
        guard let fading, fading.generation == current else { return }
        discard(fading.panel, parent: fading.parent)
        self.fading = nil
    }

    private func discard(_ panel: NSPanel, parent: NSWindow?) {
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.contentView = nil
        panel.close()
    }

    private func animate(_ duration: Double, _ changes: () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            changes()
        }
    }
}

/// 统一处理锚点与卡片的悬停：全部离开后短暂宽限再关闭，不使用全局鼠标监听或周期定时器。
/// 锚点按标识分别记录，相邻指标之间先进后出或先出后进都不会误关。
/// 固定后不再随悬停切换或关闭；点到别处、按 Esc、窗口失去焦点或关闭时解除，监听只在固定期间存在。
@MainActor
final class HoverCardCoordinator {
    private let controller = HoverCardController()
    private var anchorsInside: Set<AnyHashable> = []
    private var cardInside = false
    private var dismissTask: Task<Void, Never>?
    private var eventMonitor: Any?
    private var windowObservers: [NSObjectProtocol] = []
    var onClose: (() -> Void)?
    var isOpen: Bool { controller.isOpen }
    private(set) var isPinned = false

    /// 宽限时间覆盖指针横穿相邻指标间隙的时长，避免卡片关了又开。
    private static let grace = Duration.milliseconds(160)

    func show(anchor: NSView, content: AnyView, key: AnyHashable = 0) {
        dismissTask?.cancel()
        cardInside = false
        controller.present(anchor: anchor, content: content, key: key) { [weak self] inside in
            self?.cardInside = inside
            self?.scheduleDismissal()
        }
    }

    /// 打开并固定卡片；已固定在其他锚点时直接移过去，保持固定。
    func pin(anchor: NSView, content: AnyView, key: AnyHashable = 0) {
        show(anchor: anchor, content: content, key: key)
        guard controller.isOpen else { return }
        isPinned = true
        startPinMonitoring()
    }

    func update(content: AnyView) { controller.update(content: content) }

    func anchorHover(_ inside: Bool, id: AnyHashable = 0) {
        if inside { anchorsInside.insert(id) } else { anchorsInside.remove(id) }
        scheduleDismissal()
    }

    private func scheduleDismissal() {
        dismissTask?.cancel()
        guard controller.isOpen, !isPinned, anchorsInside.isEmpty, !cardInside else { return }
        dismissTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: Self.grace) } catch { return }
            guard let self, self.anchorsInside.isEmpty, !self.cardInside else { return }
            self.close()
        }
    }

    private func startPinMonitoring() {
        stopPinMonitoring()
        // 仅本应用内的局部事件：点击卡片和当前锚点以外的位置或按 Esc 时解除固定。
        // 点到其他指标也先关闭，随后该指标的点击会从淡出中接回卡片并固定到新位置。
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.isPinned else { return }
                if event.type == .keyDown {
                    if event.keyCode == 53 { self.close() }
                } else if !self.controller.contains(event) {
                    self.close()
                }
            }
            return event
        }
        guard let window = controller.parentWindow else { return }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            })
        }
    }

    private func stopPinMonitoring() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
    }

    func close() {
        dismissTask?.cancel()
        dismissTask = nil
        cardInside = false
        anchorsInside.removeAll()
        isPinned = false
        stopPinMonitoring()
        let wasOpen = controller.isOpen
        controller.close()
        if wasOpen { onClose?() }
    }
}

private final class CardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 圆角雾面卡片：底板铺满面板，随窗口尺寸动画伸缩；内容贴顶，换锚点时按标识交叉淡入。
private struct CardSurface: View {
    let content: AnyView
    let key: AnyHashable
    let resize: (CGSize) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 14).fill(.regularMaterial)
            RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.08), lineWidth: 0.5)
            content
                .fixedSize(horizontal: true, vertical: true)
                .onGeometryChange(for: CGSize.self) { $0.size } action: {
                    resize(CGSize(width: $0.width + 4, height: $0.height + 4))
                }
                .id(key)
                .transition(.opacity)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(2)
        .animation(.easeInOut(duration: 0.18), value: key)
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
