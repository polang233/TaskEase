import AppKit
import Foundation
import Testing
@testable import TaskEase

struct ApplicationLifecycleTests {
    @Test @MainActor func menuBarImageHasARealPointSize() {
        #expect(MenuBarIcon.image.size == NSSize(width: 18, height: 18))
        #expect(MenuBarIcon.image.isTemplate)
    }

    @Test func oneLockOwnerAndReacquireAfterClose() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("application.lock")
        var first = try ProcessFileLock.acquire(at: path)
        #expect(first != nil)
        #expect(try ProcessFileLock.acquire(at: path) == nil)
        first = nil
        let next = try ProcessFileLock.acquire(at: path)
        #expect(next != nil)
    }

    @Test func separateValidationScopesCanRunIndependently() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try ProcessFileLock.acquire(at: root.appendingPathComponent("a/application.lock"))
        let second = try ProcessFileLock.acquire(at: root.appendingPathComponent("b/application.lock"))
        #expect(first != nil)
        #expect(second != nil)
        let a = UUID(), b = UUID()
        #expect(LaunchContext.validation(a).coordinationDirectory != LaunchContext.validation(b).coordinationDirectory)
    }

    @Test func previewAndTestLaunchesHaveNoStatusItem() throws {
        let preview = try LaunchContext.parse(arguments: ["TaskEase"], environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"])
        let uiTest = try LaunchContext.parse(arguments: ["TaskEase", "--ui-testing"], environment: [:])
        let unit = try LaunchContext.parse(arguments: ["TaskEase"], environment: ["XCTestConfigurationFilePath": "test"])
        for context in [preview, uiTest, unit] {
            #expect(!context.hasStatusItem)
            #expect(context.usesFixtures)
            #expect(context.coordinationDirectory == nil)
        }
        #expect(LaunchContext.application.hasStatusItem)
        #expect(LaunchContext.application.opensManagement)
        #expect(!LaunchContext.application.usesFixtures)
        #expect(throws: (any Error).self) {
            try LaunchContext.parse(arguments: ["TaskEase", "--instance-test-scope", "invalid"], environment: [:])
        }
    }

    @Test @MainActor func managementWindowReusesItsWindowAndChangesDockPolicy() {
        let policy = NSApp.activationPolicy()
        let model = AppModel(preview: true)
        defer { model.closeManagement(); model.shutdown(); NSApp.setActivationPolicy(policy) }
        model.showManagement()
        let first = NSApp.windows.first { $0.identifier?.rawValue == "management-window" }
        #expect(first != nil)
        #expect(first?.isVisible == true)
        #expect(NSApp.activationPolicy() == .regular)
        model.showManagement()
        let windows = NSApp.windows.filter { $0.identifier?.rawValue == "management-window" }
        #expect(windows.count == 1)
        #expect(windows.first === first)
        model.closeManagement()
        #expect(!model.managementIsOpen)
        #expect(NSApp.activationPolicy() == .accessory)
        model.showManagement()
        #expect(model.managementIsOpen)
        #expect(first?.isVisible == true)
        #expect(NSApp.activationPolicy() == .regular)
    }
}
