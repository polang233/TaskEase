import SwiftUI

/// 展开箭头、标题和行内空白共享一个原生按钮，同时支持键盘操作。
struct FullRowDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { configuration.isExpanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption).accessibilityHidden(true)
                    configuration.label
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityValue(configuration.isExpanded ? Text("a11y.expanded") : Text("a11y.collapsed"))
            if configuration.isExpanded { configuration.content }
        }
    }
}
