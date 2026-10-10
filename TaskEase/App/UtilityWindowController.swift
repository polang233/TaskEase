import AppKit
import SwiftUI

enum UtilityWindowKind: String {
    case settings, help, about, license

    var title: String {
        switch self {
        case .settings: "轻程设置"
        case .help: "轻程帮助"
        case .about: "关于轻程"
        case .license: "开源许可证"
        }
    }

    var size: NSSize {
        switch self {
        case .settings: NSSize(width: 560, height: 510)
        case .help: NSSize(width: 680, height: 580)
        case .about: NSSize(width: 440, height: 440)
        case .license: NSSize(width: 680, height: 600)
        }
    }
}

@MainActor
final class UtilityWindowController: NSWindowController, NSWindowDelegate {
    private weak var model: AppModel?
    private let kind: UtilityWindowKind

    init(kind: UtilityWindowKind, model: AppModel) {
        self.kind = kind
        self.model = model
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if kind != .about { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: kind.size),
                              styleMask: style, backing: .buffered, defer: false)
        window.title = kind.title
        window.identifier = NSUserInterfaceItemIdentifier("utility-\(kind.rawValue)")
        window.minSize = kind.size
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let hosting = NSHostingController(rootView: UtilityRoot(kind: kind, model: model))
        hosting.sizingOptions = []
        window.contentViewController = hosting
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
            }
        }.preferredColorScheme(model.preferences.theme.colorScheme)
    }
}
