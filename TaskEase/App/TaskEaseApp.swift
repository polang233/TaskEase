import SwiftUI
import AppKit
import Darwin

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
        alert.messageText = "轻程无法启动"
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
        do {
            if try !ApplicationSession.shared.claim() { exit(0) }
        } catch {
            AppDelegate.showStartupError(error)
            exit(1)
        }
    }
    var body: some Scene {
        MenuBarExtra(isInserted: .constant(LaunchContext.current.hasStatusItem)) {
            MenuPanel(model: delegate.model)
        } label: {
            Image(nsImage: MenuBarIcon.image).accessibilityLabel("轻程")
        }.menuBarExtraStyle(.window)
            .commands {
                CommandGroup(replacing: .appInfo) {
                    Button("关于轻程") { delegate.model.showUtility(.about) }
                }
                CommandGroup(after: .appInfo) {
                    Button("应用管理") { delegate.model.showManagement() }
                        .keyboardShortcut("1", modifiers: .command)
                }
                CommandGroup(replacing: .appSettings) {
                    Button("设置…") { delegate.model.showUtility(.settings) }
                        .keyboardShortcut(",", modifiers: .command)
                }
                CommandGroup(after: .windowList) {
                    Button("关闭窗口") { NSApp.keyWindow?.performClose(nil) }
                        .keyboardShortcut("w", modifiers: .command)
                }
                CommandGroup(replacing: .help) {
                    Button("轻程帮助") { delegate.model.showUtility(.help) }
                        .keyboardShortcut("?", modifiers: .command)
                }
            }
    }
}
