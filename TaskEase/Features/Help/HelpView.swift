import SwiftUI

/// 应用内使用说明，解释资源指标与后台规则的操作流程。
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    BrandMark(size: 36)
                    Text("让后台应用少占资源").font(.title2.weight(.semibold))
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("设置后台规则").font(.headline)
                    Text("1. 在“运行中的应用”里选择应用。")
                    Text("2. 打开“限制后台资源”，设置等待时间和 CPU 使用上限。")
                    Text("3. 打开顶部的“启用后台限制”总开关。")
                    Text("应用离开前台或隐藏后开始计时，等待结束后执行规则。切回前台恢复正常运行。")
                        .foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("理解 CPU 使用上限").font(.headline)
                    Text("应用 CPU 100% 约等于一个核心满载，包含该应用的自有辅助进程。20% 表示平均使用一个核心的五分之一。")
                    Text("限制可能影响后台声音和连接心跳。调整上限后，观察应用是否还能完成你需要的后台工作。")
                        .foregroundStyle(.secondary)
                    Text("高级选项中的“仅降低后台优先级”让前台任务优先获得资源，没有固定 CPU 上限。")
                        .foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("管理已保存的规则").font(.headline)
                    Text("在“已配置规则”中修改应用规则。应用退出后仍保留规则，下次运行时继续使用。")
                    Text("关闭总开关可暂停全部规则；关闭某个应用的限制则保持该应用原样；“移除规则”删除它的配置。")
                        .foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("查看占用信息").font(.headline)
                    Text("整机 CPU 按全部核心的总能力计算；GPU 是整机驱动利用率估计值；热状态表示发热对系统运行的影响程度。")
                    Text("系统应用默认隐藏，可在列表或设置中开启显示。设置中还能选择外观和显示刷新间隔。")
                        .foregroundStyle(.secondary)
                }
            }.font(.callout).textSelection(.enabled).padding(28)
        }
    }
}

#Preview("帮助") {
    HelpView().frame(width: 680, height: 580)
}
