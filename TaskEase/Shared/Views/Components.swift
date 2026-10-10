import SwiftUI
import AppKit

struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        Image("TaskEaseMark").resizable().scaledToFit()
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

@MainActor
private enum ApplicationIcons {
    static var images: [String: NSImage] = [:]

    static func image(at path: String) -> NSImage {
        if let cached = images[path] { return cached }
        if images.count > 128 { images.removeAll() }
        let image = NSWorkspace.shared.icon(forFile: path)
        images[path] = image
        return image
    }
}

struct AppIcon: View {
    let app: AppReading
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let path = app.bundlePaths.first {
                Image(nsImage: ApplicationIcons.image(at: path)).resizable()
            } else {
                Image(systemName: "app").resizable().scaledToFit().padding(5).foregroundStyle(.secondary)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct StatusLabel: View {
    let status: RuleStatus

    private var color: Color {
        switch status {
        case .gentle, .budget: .green
        case .waiting: .orange
        default: .secondary
        }
    }

    var body: some View {
        Text(status.title).font(.caption).foregroundStyle(color)
    }
}

struct BackgroundControlToggle: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Toggle("启用后台限制", isOn: Binding(get: { model.enabled }, set: { model.setEnabled($0) }))
                .toggleStyle(.switch)
                .disabled(!model.canEnable)
                .accessibilityIdentifier("management-toggle")
                .help(model.canEnable ? "统一启用或暂停已配置的后台规则。" : "先为一个应用开启后台限制。")
            if !model.canEnable {
                Text("先为应用设置后台规则").font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("configure-rules-hint")
            }
        }
    }
}

struct SystemStrip: View {
    let reading: SystemReading

    var body: some View {
        HStack(spacing: 18) {
            Label("CPU \(Display.percent(reading.cpuPercent))", systemImage: "cpu").monospacedDigit()
                .help("整机 CPU 占用，以全部 CPU 核心的总能力计算。")
            Label("GPU \(Display.percent(reading.gpuPercent))", systemImage: "square.3.layers.3d").monospacedDigit()
                .help("整机 GPU 驱动利用率估计值，无法归属某个应用。缺失时显示 —。")
            Spacer(minLength: 10)
            Label(reading.thermalLabel, systemImage: "thermometer.medium")
                .foregroundStyle(reading.thermalLabel == "正常" ? Color.secondary : Color.orange)
                .help("系统热状态，表示发热对运行的影响程度。")
        }.font(.callout).padding(.horizontal, 20).padding(.vertical, 11)
    }
}
