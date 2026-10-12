import AppKit
import SwiftUI

/// 复用管理窗口，处理激活、最小化恢复与关闭后的 Dock 状态。
@MainActor
final class ManagementWindowController: NSWindowController, NSWindowDelegate {
    private weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = String(localized: "app.name")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        // 空的 unified 工具栏加高标题栏，系统会把红绿灯放在加高后的竖直中线上，页眉再按实测尺寸对齐。
        window.toolbar = NSToolbar(identifier: "TaskEase.ManagementToolbar")
        window.toolbarStyle = .unified
        window.identifier = NSUserInterfaceItemIdentifier("management-window")
        window.minSize = NSSize(width: 840, height: 580)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let hosting = NSHostingController(rootView: ContentView(model: model, titlebar: .measure(window)))
        hosting.sizingOptions = .minSize
        window.contentViewController = hosting
        super.init(window: window)
        window.delegate = self
        if !model.preview {
            window.setFrameAutosaveName("TaskEase.ManagementWindow")
        }
        if model.preview || !window.setFrameUsingName("TaskEase.ManagementWindow") { window.center() }
    }

    required init?(coder: NSCoder) { return nil }

    func present() {
        NSApp.setActivationPolicy(.regular)
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        model?.managementDidClose()
    }
}
