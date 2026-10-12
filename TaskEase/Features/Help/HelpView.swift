import SwiftUI

/// 应用内使用说明，按操作顺序简要列出。
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    BrandMark(size: 32)
                    Text("common.help").font(.title2.weight(.semibold))
                }
                section("help.start.title", ["help.start.1", "help.start.2", "help.start.3"])
                section("help.timing.title", ["help.timing.1", "help.timing.2"])
                section("help.cpu.title", ["help.cpu.1", "help.cpu.2", "help.cpu.3"])
                section("help.overview.title", ["help.overview.1", "help.overview.2"])
                section("help.language.title", ["help.language.1"])
            }.font(.callout).textSelection(.enabled).padding(28)
        }
    }

    private func section(_ title: LocalizedStringKey, _ lines: [LocalizedStringKey]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            ForEach(lines.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "•").foregroundStyle(.secondary)
                    Text(lines[index])
                }
            }
        }
    }
}

#Preview("帮助") {
    HelpView().frame(width: 560, height: 520)
}
