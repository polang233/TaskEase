import AppKit
import SwiftUI

@MainActor
final class ManagementWindowController: NSWindowController, NSWindowDelegate {
    private weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 650),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "轻程"
        window.identifier = NSUserInterfaceItemIdentifier("management-window")
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.contentViewController = NSHostingController(rootView: ContentView(model: model))
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
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model?.managementDidClose()
    }
}
