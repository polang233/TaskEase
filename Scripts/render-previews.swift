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
        app.setActivationPolicy(.prohibited)
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
        model.shutdown()
    }

    /// 使用离屏窗口承载 AppKit 控件，导出视图内容而非桌面截图。
    static func save<V: View>(_ view: V, size: NSSize, appearance: NSAppearance.Name, to url: URL) throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        let hosted = NSHostingView(rootView: view
            .environment(\.colorScheme, appearance == .aqua ? .light : .dark)
            .background(Color(nsColor: .windowBackgroundColor)))
        hosted.appearance = window.appearance
        hosted.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosted
        window.layoutIfNeeded()
        let deadline = Date().addingTimeInterval(0.5)
        while Date() < deadline { _ = RunLoop.current.run(mode: .default, before: deadline) }
        hosted.layoutSubtreeIfNeeded()
        guard let bitmap = hosted.bitmapImageRepForCachingDisplay(in: hosted.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        hosted.cacheDisplay(in: hosted.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
        window.close()
        print(url.lastPathComponent)
    }
}
