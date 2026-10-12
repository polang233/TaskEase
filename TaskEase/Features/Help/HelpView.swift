import SwiftUI

/// 应用内使用说明，按操作顺序简要列出。
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    BrandMark(size: 32)
                    Text("使用帮助").font(.title2.weight(.semibold))
                }
                section("开始使用", [
                    "选择应用，打开“限制后台资源”。",
                    "设置生效时机和 CPU 上限。",
                    "打开顶部“启用后台限制”。"
                ])
                section("生效时机", [
                    "应用离开前台或隐藏后开始计时，到时开始限制，回到前台立即恢复。",
                    "拖到最左侧为“始终限制”，前台使用时也会限制。"
                ])
                section("CPU 上限", [
                    "100% 等于一个核心满载，应用的辅助进程共享这个额度。",
                    "限制通过短暂暂停实现，可能影响声音和网络连接。",
                    "“仅降低后台优先级”不设上限，只让前台优先。"
                ])
                section("系统概览", [
                    "点击 CPU、GPU、内存或温度查看详情，指针移开后关闭。",
                    "颜色从绿到红表示占用由低到高。样式可在设置中切换。"
                ])
            }.font(.callout).textSelection(.enabled).padding(28)
        }
    }

    private func section(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•").foregroundStyle(.secondary)
                    Text(line)
                }
            }
        }
    }
}

#Preview("帮助") {
    HelpView().frame(width: 560, height: 520)
}
