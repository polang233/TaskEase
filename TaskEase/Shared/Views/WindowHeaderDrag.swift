import SwiftUI
import AppKit

/// 品牌区域与标题空白作为窗口拖动入口，操作按钮保留各自的点击行为。
/// 用覆盖在非交互内容上的 AppKit 视图实现，macOS 14 同样可用，也保留双击标题栏的系统行为。
struct WindowHeaderDrag: ViewModifier {
    let enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.overlay(WindowDragArea()) }
        else { content }
    }
}

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 { performTitlebarDoubleClick(window) }
            else { window.performDrag(with: event) }
        }

        /// 跟随“桌面与程序坞 → 连按窗口标题栏”的系统设置。
        private func performTitlebarDoubleClick(_ window: NSWindow) {
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window.performMiniaturize(nil)
            case "None": break
            default: window.performZoom(nil)
            }
        }
    }
}
