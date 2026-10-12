import AppKit
import SwiftUI

// 独立预览程序使用自己的资源包，正式应用仍由 Xcode 生成资源符号。
extension ImageResource {
    static let taskEaseMenu = ImageResource(name: "TaskEaseMenu", bundle: .main)
}

/// 用实际 SwiftUI 视图和示例模型导出文档图片，全程不读取用户规则。
@main @MainActor
struct PreviewRenderer {
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let destination = URL(fileURLWithPath: CommandLine.arguments[1])
        let model = AppModel(preview: true)
        model.setRule("example.browser", rule: AppRule(mode: .budget, cpuPercent: 20, delaySeconds: 3))
        model.selectedID = "example.browser"
        model.setEnabled(true)
        try save(ContentView(model: model), size: NSSize(width: 1000, height: 720),
                 appearance: .aqua, to: destination.appendingPathComponent("management-preview.png"))
        model.setEnabled(false)
        model.updatePreferences { $0.theme = .dark }
        try save(MenuPanel(model: model), size: NSSize(width: 420, height: 244),
                 appearance: .darkAqua, to: destination.appendingPathComponent("menu-preview.png"))
        try save(SettingsView(model: model), size: NSSize(width: 560, height: 700),
                 appearance: .darkAqua, to: destination.appendingPathComponent("settings-preview.png"))
        try save(AboutView(model: model), size: NSSize(width: 580, height: 430),
                 appearance: .darkAqua, to: destination.appendingPathComponent("about-preview.png"))
        try save(UsageStatisticsView(model: model), size: NSSize(width: 580, height: 460),
                 appearance: .darkAqua, to: destination.appendingPathComponent("statistics-preview.png"))
        try save(HStack(alignment: .top, spacing: 16) {
            MetricDetails(metric: .cpu, reading: model.system)
            MetricDetails(metric: .gpu, reading: model.system)
            MetricDetails(metric: .memory, reading: model.system)
        }.padding(16), size: NSSize(width: 732, height: 190), appearance: .aqua,
            to: destination.appendingPathComponent("metric-details-preview.png"))
        let busy = SystemReading(cpuPercent: 23, gpuPercent: 61, thermalLabel: "正常",
            memory: .init(usedBytes: 19 * 1_073_741_824, totalBytes: 24 * 1_073_741_824, compressedBytes: 2 * 1_073_741_824),
            network: .init(receiveRate: 12_345_678, sendRate: 345_678), temperatureCelsius: 78.4)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            try save(VStack(alignment: .leading, spacing: 0) {
                ForEach(MetricDisplayStyle.allCases, id: \.self) { style in
                    SystemStrip(reading: busy, style: style)
                    Divider()
                }
            }, size: NSSize(width: 720, height: 132), appearance: appearance,
                to: destination.appendingPathComponent("metric-styles-\(name).png"))
        }
        model.apply(MonitoringSnapshot(apps: AppModel.exampleApps,
            system: SystemReading(cpuPercent: 92, gpuPercent: 66, thermalLabel: "较高",
                memory: .init(usedBytes: 21 * 1_073_741_824, totalBytes: 24 * 1_073_741_824, compressedBytes: 3 * 1_073_741_824),
                network: .init(receiveRate: 95_123_456, sendRate: 12_345_678), temperatureCelsius: 86.7)))
        try save(SystemStrip(reading: model.system, isPaused: true), size: NSSize(width: 840, height: 42),
                 appearance: .darkAqua, to: destination.appendingPathComponent("paused-preview.png"))
        model.shutdown()
    }

    /// 把窗口短暂放到屏幕上并截取自身窗口的合成图像；Liquid Glass 等由窗口服务器合成的效果
    /// 无法通过 cacheDisplay 呈现。截取自身窗口无需录屏权限，失败时退回离屏渲染。
    static func save<V: View>(_ view: V, size: NSSize, appearance: NSAppearance.Name, to url: URL) throws {
        let origin = NSScreen.main?.visibleFrame.origin ?? .zero
        let window = PreviewWindow(contentRect: NSRect(origin: NSPoint(x: origin.x + 40, y: origin.y + 40), size: size),
                                   styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.appearance = NSAppearance(named: appearance)
        let hosted = NSHostingView(rootView: view
            .environment(\.colorScheme, appearance == .aqua ? .light : .dark)
            .background(Color(nsColor: .windowBackgroundColor)))
        hosted.appearance = window.appearance
        hosted.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosted
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        let deadline = Date().addingTimeInterval(0.8)
        while Date() < deadline { _ = RunLoop.current.run(mode: .default, before: deadline) }
        hosted.layoutSubtreeIfNeeded()
        let bitmap: NSBitmapImageRep
        if let image = windowImage(window) {
            bitmap = NSBitmapImageRep(cgImage: image)
        } else {
            print("合成截图不可用，改用离屏渲染：\(url.lastPathComponent)")
            guard let cached = hosted.bitmapImageRepForCachingDisplay(in: hosted.bounds) else {
                throw CocoaError(.fileWriteUnknown)
            }
            hosted.cacheDisplay(in: hosted.bounds, to: cached)
            bitmap = cached
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
        window.orderOut(nil)
        window.close()
        print(url.lastPathComponent)
    }

    /// CGWindowListCreateImage 在新 SDK 中不可直接调用，运行时按符号取得；仅用于本机预览。
    private static func windowImage(_ window: NSWindow) -> CGImage? {
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let capture = unsafeBitCast(symbol, to: Capture.self)
        // kCGWindowListOptionIncludingWindow = 1 << 3，kCGWindowImageBoundsIgnoreFraming = 1
        return capture(.null, 1 << 3, UInt32(window.windowNumber), 1)?.takeRetainedValue()
    }
}

/// 无边框窗口默认不能成为 key，控件会以非活动外观绘制。
private final class PreviewWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
