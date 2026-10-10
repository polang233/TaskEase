import XCTest
import AppKit

@MainActor
final class TaskEaseUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testManagementWindowSearchAndReadOnlyApp() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
        let window = app.windows["轻程"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let search = app.textFields["app-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("Finder")
        let queryCommitted = NSPredicate(format: "value == %@", "Finder")
        expectation(for: queryCommitted, evaluatedWith: search)
        waitForExpectations(timeout: 5)
        if !window.staticTexts["Finder"].waitForExistence(timeout: 5) {
            let tree = XCTAttachment(string: window.debugDescription)
            tree.lifetime = .keepAlways; add(tree)
            let screenshot = XCTAttachment(screenshot: window.screenshot())
            screenshot.lifetime = .keepAlways; add(screenshot)
            XCTFail("Finder search result missing. Search value: \(String(describing: search.value))\n\(window.debugDescription)")
            return
        }
        window.staticTexts["Finder"].firstMatch.click()
        XCTAssertTrue(window.staticTexts["系统应用只用于观察。"].waitForExistence(timeout: 5))
        app.terminate()
    }

    func testCloseAndReopenManagementKeepsSameApplication() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--instance-test-scope", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        app.activate()
        XCTAssertTrue(app.windows["轻程"].waitForExistence(timeout: 10))
        var runner = Bundle(for: Self.self).bundleURL
        while runner.pathExtension != "app" && runner.path != "/" { runner.deleteLastPathComponent() }
        let applicationURL = runner.deletingLastPathComponent().appendingPathComponent("TaskEase.app")
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.github.polang233.TaskEase")
            .first { $0.bundleURL?.path == applicationURL.path }
        XCTAssertNotNil(running)
        let originalPID = running?.processIdentifier
        app.typeKey("w", modifierFlags: .command)
        let deadline = Date().addingTimeInterval(3)
        while running?.activationPolicy != .accessory && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(running?.activationPolicy, .accessory)
        XCTAssertFalse(running?.isTerminated ?? true)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = false
        let reopened = expectation(description: "Reopen the same application")
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { _, _ in
            reopened.fulfill()
        }
        wait(for: [reopened], timeout: 10)
        XCTAssertEqual(running?.processIdentifier, originalPID)
        XCTAssertEqual(running?.activationPolicy, .regular)
        app.activate()
        XCTAssertTrue(app.windows["轻程"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.matching(identifier: "轻程").count, 1)
    }

    func testPauseAutomaticManagementAndRestore() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
        let window = app.windows["轻程"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let control = window.switches["management-toggle"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        control.click()
        control.click()
        XCTAssertTrue(window.staticTexts["轻程"].exists)
        app.terminate()
    }
}
