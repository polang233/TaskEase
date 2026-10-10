import SwiftUI
import AppKit

/// Observe the hosting window instead of treating the view's lifetime as visibility.
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
