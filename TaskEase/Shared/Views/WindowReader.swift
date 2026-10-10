import SwiftUI
import AppKit

/// 跟踪真实宿主窗口，避免用视图生命周期误判菜单面板可见性。
struct WindowReader: NSViewRepresentable {
    let onWindowChange: @MainActor (NSWindow?) -> Void

    func makeNSView(context: Context) -> Probe {
        let view = Probe(frame: .zero)
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ view: Probe, context: Context) { view.onWindowChange = onWindowChange }

    final class Probe: NSView {
        var onWindowChange: @MainActor (NSWindow?) -> Void = { _ in }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let attachedWindow = window
            let callback = onWindowChange
            Task { @MainActor in callback(attachedWindow) }
        }
    }
}
