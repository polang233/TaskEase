import SwiftUI
import AppKit
import Darwin

/// 处理应用启动、重复打开与退出时的进程恢复。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var model = AppModel(preview: LaunchContext.current.usesFixtures)

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = model
        do {
            try ApplicationSession.shared.startHandlingReopen { [weak self] in self?.model.showManagement() }
        } catch {
            showStartupError(error)
            NSApp.terminate(nil)
            return
        }
        if LaunchContext.current.opensManagement || CommandLine.arguments.contains("--show-management") {
            model.showManagement()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.showManagement()
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
        ApplicationSession.shared.finish()
    }

    static func showStartupError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = String(localized: "error.launch.title")
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
    private func showStartupError(_ error: Error) { Self.showStartupError(error) }
}

@main @MainActor
struct TaskEaseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        let args = CommandLine.arguments
        if args.contains("--limiter-worker") { NativeWorker.run(); exit(0) }
        if args.contains("--self-test-worker") { NativeWorker.run(testing: true); exit(0) }
        if args.contains("--burner") { SelfCheck.burn(); exit(0) }
        if args.contains("--snapshot") { SelfCheck.snapshot(); exit(0) }
        if args.contains("--self-test") { exit(SelfCheck.run() ? 0 : 1) }
        if args.contains("--analytics-check") { exit(AnalyticsCheck.run() ? 0 : 1) }
        do {
            if try !ApplicationSession.shared.claim() { exit(0) }
        } catch {
            AppDelegate.showStartupError(error)
            exit(1)
        }
    }
    var body: some Scene {
        // 用户在设置中关闭，或按住 ⌘ 把图标拖出菜单栏时，都保存为同一个偏好。
        MenuBarExtra(isInserted: Binding(
            get: { LaunchContext.current.hasStatusItem && delegate.model.preferences.showMenuBarIcon },
            set: { value in delegate.model.updatePreferences { $0.showMenuBarIcon = value } })) {
            MenuPanel(model: delegate.model)
        } label: {
            Image(nsImage: MenuBarIcon.image).accessibilityLabel("app.name")
        }.menuBarExtraStyle(.window)
            .commands {
                CommandGroup(replacing: .appInfo) {
                    Button("menu.about") { delegate.model.showUtility(.about) }
                }
                CommandGroup(after: .appInfo) {
                    Button("menu.manageApps") { delegate.model.showManagement() }
                        .keyboardShortcut("1", modifiers: .command)
                }
                CommandGroup(replacing: .appSettings) {
                    Button("menu.settings") { delegate.model.showUtility(.settings) }
                        .keyboardShortcut(",", modifiers: .command)
                }
                CommandGroup(after: .windowList) {
                    Button("menu.closeWindow") { NSApp.keyWindow?.performClose(nil) }
                        .keyboardShortcut("w", modifiers: .command)
                }
                CommandGroup(replacing: .help) {
                    Button("menu.help") { delegate.model.showUtility(.help) }
                        .keyboardShortcut("?", modifiers: .command)
                }
            }
    }
}
