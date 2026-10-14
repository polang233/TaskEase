import SwiftUI

/// 上传（橙色箭头）、下载（蓝色箭头）上下两行同等显示，单位随速度切换，宽度固定避免整行跳动。
struct NetworkRateStack: View {
    let reading: SystemNetworkReading?
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            line("arrow.up", reading?.sendRate, color: .orange)
            line("arrow.down", reading?.receiveRate, color: .blue)
        }.font(.system(size: compact ? 9.5 : 10.5).monospacedDigit())
            .frame(width: compact ? 64 : 76, height: 24, alignment: .leading)
            .accessibilityHidden(true)
    }

    private func line(_ icon: String, _ rate: Double?, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: compact ? 7 : 8, weight: .bold)).foregroundStyle(color)
            Text(Display.compactRate(rate))
        }
    }
}
