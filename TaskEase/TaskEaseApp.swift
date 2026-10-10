import SwiftUI
import AppKit
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var model: AppModel = {
        let args = CommandLine.arguments
        let isolated = args.contains("--ui-testing") ||
            ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" ||
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        return AppModel(preview: isolated)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = model
        if CommandLine.arguments.contains("--ui-testing") || CommandLine.arguments.contains("--show-management") {
            model.showManagement()
        }
    }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
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
    }
    var body: some Scene {
        MenuBarExtra("TaskEase", systemImage: "leaf") {
            MenuPanel(model: delegate.model)
        }.menuBarExtraStyle(.window)
    }
}
