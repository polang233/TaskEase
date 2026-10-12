import SwiftUI

/// 新系统采用原生滑轨式选择条，旧系统保持分段控件的键盘与辅助功能支持。
private struct SelectionRailStyle: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 27.0, *) { content.pickerStyle(.tabs) }
        else { content.pickerStyle(.segmented) }
    }
}

extension View {
    func selectionRail() -> some View { modifier(SelectionRailStyle()) }
}
