import XCTest
import AppKit

@MainActor
final class TaskEaseUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.loginwindow" {
            throw XCTSkip("Unlock the Mac and return to the desktop before running UI tests.")
        }
    }

    private func launchFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.windows["轻程"].waitForExistence(timeout: 10))
        return app
    }

    func testSystemFilterSearchAndReadOnlyApp() throws {
        let app = launchFixture()
        defer { app.terminate() }
        let window = app.windows["轻程"]
        XCTAssertFalse(window.staticTexts["Finder"].exists)
        let filter = window.checkBoxes["show-system-apps"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.click()
        let search = window.textFields["app-search"]
        search.click()
        search.typeText("Finder")
        expectation(for: NSPredicate(format: "value == %@", "Finder"), evaluatedWith: search)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(window.staticTexts["Finder"].waitForExistence(timeout: 5))
        window.staticTexts["Finder"].firstMatch.click()
        XCTAssertTrue(window.staticTexts["系统应用只用于观察。"].waitForExistence(timeout: 5))
        XCTAssertFalse(window.switches["app-rule-toggle"].isEnabled)
    }

    func testConfigureRuleGlobalSwitchAndSavedList() throws {
        let app = launchFixture()
        defer { app.terminate() }
        let window = app.windows["轻程"]
        let global = window.switches["management-toggle"]
        XCTAssertTrue(global.waitForExistence(timeout: 5))
        XCTAssertFalse(global.isEnabled)
        XCTAssertTrue(window.staticTexts["先为应用设置后台规则"].exists)
        window.staticTexts["网页浏览器"].firstMatch.click()
        let rule = window.switches["app-rule-toggle"]
        XCTAssertTrue(rule.waitForExistence(timeout: 5))
        rule.click()
        XCTAssertTrue(global.isEnabled)
        XCTAssertTrue(window.sliders["cpu-budget"].exists)
        XCTAssertTrue(window.staticTexts["规则已保存，打开顶部总开关后执行。"].exists)
        global.click()
        global.click()
        XCTAssertTrue(window.staticTexts["规则已保存，打开顶部总开关后执行。"].exists)
        let configured = window.descendants(matching: .any).matching(identifier: "已配置规则").firstMatch
        XCTAssertTrue(configured.waitForExistence(timeout: 5))
        configured.click()
        XCTAssertTrue(window.staticTexts["网页浏览器"].exists)
        let image = XCTAttachment(screenshot: window.screenshot())
        image.name = "ManagementConfigured"
        image.lifetime = .keepAlways
        add(image)
        window.buttons["remove-rule"].click()
        XCTAssertTrue(window.staticTexts["还没有后台规则"].waitForExistence(timeout: 5))
        XCTAssertFalse(global.isEnabled)
    }

    func testSettingsThemeRefreshHelpAndAbout() throws {
        let app = launchFixture()
        defer { app.terminate() }
        let window = app.windows["轻程"]
        window.buttons["open-settings"].click()
        let settings = app.windows["轻程设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        let dark = settings.descendants(matching: .any).matching(identifier: "深色").firstMatch
        XCTAssertTrue(dark.waitForExistence(timeout: 5))
        dark.click()
        let refresh = settings.popUpButtons["display-refresh-interval"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        refresh.click()
        app.menuItems["10 秒"].click()
        XCTAssertTrue(window.staticTexts["显示每 10 秒更新"].waitForExistence(timeout: 5))
        let image = XCTAttachment(screenshot: settings.screenshot())
        image.name = "SettingsDark"
        image.lifetime = .keepAlways
        add(image)
        settings.buttons["关于轻程"].click()
        let about = app.windows["关于轻程"]
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        XCTAssertTrue(about.staticTexts["TaskEase · 轻程"].exists)
        about.buttons["使用帮助"].click()
        let help = app.windows["轻程帮助"]
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        XCTAssertTrue(help.staticTexts["让后台应用少占资源"].exists)
        app.typeKey("w", modifierFlags: .command)
        app.typeKey("w", modifierFlags: .command)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(window.exists)
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
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { _, _ in reopened.fulfill() }
        wait(for: [reopened], timeout: 10)
        XCTAssertEqual(running?.processIdentifier, originalPID)
        XCTAssertEqual(running?.activationPolicy, .regular)
        app.activate()
        XCTAssertTrue(app.windows["轻程"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.matching(identifier: "轻程").count, 1)
    }
}
