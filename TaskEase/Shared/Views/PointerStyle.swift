import SwiftUI
import AppKit

/// 可点击区域悬停时显示手形指针。macOS 15 起使用系统指针样式，较早系统用光标栈。
private struct PointingHand: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 15.0, *) { content.pointerStyle(.link) }
        else { content.onHover { inside in inside ? NSCursor.pointingHand.push() : NSCursor.pop() } }
    }
}

extension View {
    func pointingHand() -> some View { modifier(PointingHand()) }
}
