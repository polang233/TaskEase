import AppKit
import SwiftUI

enum UtilityWindowKind: String {
    case settings, help, about, license, statistics, update

    var title: String {
        switch self {
        case .settings: String(localized: "window.settings")
        case .help: String(localized: "menu.help")
        case .about: String(localized: "menu.about")
        case .license: String(localized: "window.license")
        case .statistics: String(localized: "window.statistics")
        case .update: String(localized: "window.update")
        }
    }

    var size: NSSize {
        switch self {
        case .settings: NSSize(width: 560, height: 700)
        case .help: NSSize(width: 560, height: 520)
        case .about: NSSize(width: 580, height: 430)
        case .license: NSSize(width: 680, height: 600)
        case .statistics: NSSize(width: 580, height: 460)
        case .update: NSSize(width: 480, height: 400)
        }
    }

    /// 可调整的窗口允许缩小，内容随窗口滚动；关于窗口固定尺寸。
    var minimumSize: NSSize {
        switch self {
        case .settings: NSSize(width: 480, height: 360)
        case .help: NSSize(width: 460, height: 360)
        case .about: size
        case .license: NSSize(width: 480, height: 360)
        case .statistics: size
        case .update: size
        }
    }
}

/// 按用途复用设置、帮助、关于和许可证窗口。
@MainActor
final class UtilityWindowController: NSWindowController, NSWindowDelegate {
    private weak var model: AppModel?
    private let kind: UtilityWindowKind

    init(kind: UtilityWindowKind, model: AppModel) {
        self.kind = kind
        self.model = model
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if kind != .about && kind != .update { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: kind.size),
                              styleMask: style, backing: .buffered, defer: false)
        window.title = kind.title
        window.identifier = NSUserInterfaceItemIdentifier("utility-\(kind.rawValue)")
        window.contentMinSize = kind.minimumSize
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let hosting = NSHostingController(rootView: UtilityRoot(kind: kind, model: model))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(kind.size)
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        NSApp.setActivationPolicy(.regular)
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) { model?.utilityDidClose(kind) }
}

private struct UtilityRoot: View {
    let kind: UtilityWindowKind
    @Bindable var model: AppModel

    var body: some View {
        Group {
            switch kind {
            case .settings: SettingsView(model: model)
            case .help: HelpView()
            case .about: AboutView(model: model)
            case .license: LicenseView()
            case .statistics: UsageStatisticsView(model: model)
            case .update: UpdateView(model: model)
            }
        }
        // 托管视图的最小布局约束与窗口最小尺寸一致，防止关于窗口被压缩，其余窗口内容可滚动。
        .frame(minWidth: kind.minimumSize.width, maxWidth: .infinity,
               minHeight: kind.minimumSize.height, maxHeight: .infinity)
    }
}
