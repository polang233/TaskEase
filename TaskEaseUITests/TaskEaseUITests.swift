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
        let menu = window.descendants(matching: .any).matching(identifier: "app-sort").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.click()
        let filter = app.menuItems["显示系统应用"]
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
        XCTAssertFalse(window.staticTexts["先为应用设置后台规则"].exists)
        window.buttons["management-unavailable"].click()
        XCTAssertTrue(app.staticTexts["先为应用设置后台规则"].waitForExistence(timeout: 5))
        window.staticTexts["网页浏览器"].firstMatch.click()
        let rule = window.switches["app-rule-toggle"]
        XCTAssertTrue(rule.waitForExistence(timeout: 5))
        rule.click()
        XCTAssertTrue(global.isEnabled)
        XCTAssertTrue(window.sliders["cpu-budget"].exists)
        XCTAssertTrue(window.switches["volume-toggle"].exists)
        // 性能限制、后台音量和降低优先级可以组合；只保留降低优先级时规则仍然有效。
        window.switches["priority-toggle"].click()
        window.switches["performance-toggle"].click()
        XCTAssertFalse(window.sliders["cpu-budget"].exists)
        XCTAssertTrue(global.isEnabled)
        window.switches["performance-toggle"].click()
        XCTAssertTrue(window.sliders["cpu-budget"].waitForExistence(timeout: 5))
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
        let foregroundOnly = settings.checkBoxes["foreground-display-only"]
        XCTAssertTrue(foregroundOnly.waitForExistence(timeout: 5))
        XCTAssertEqual((foregroundOnly.value as? NSNumber)?.intValue, 1)
        foregroundOnly.click()
        XCTAssertEqual((foregroundOnly.value as? NSNumber)?.intValue, 0)
        foregroundOnly.click()
        XCTAssertEqual((foregroundOnly.value as? NSNumber)?.intValue, 1)
        let refresh = settings.popUpButtons["display-refresh-interval"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        refresh.click()
        app.menuItems["10 秒"].click()
        XCTAssertEqual(refresh.value as? String, "10 秒")
        let image = XCTAttachment(screenshot: settings.screenshot())
        image.name = "SettingsDark"
        image.lifetime = .keepAlways
        add(image)
        settings.buttons["关于轻程"].click()
        let about = app.windows["关于轻程"]
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        XCTAssertTrue(about.staticTexts["TaskEase · 轻程"].exists)
        about.buttons["许可证"].click()
        let license = app.windows["开源许可证"]
        XCTAssertTrue(license.waitForExistence(timeout: 5))
        let body = license.descendants(matching: .any).matching(identifier: "license-text").firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        let content = body.value as? String ?? body.label
        if !content.contains("Free Software Foundation") {
            let tree = XCTAttachment(string: license.debugDescription)
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertTrue(content.contains("Free Software Foundation"))
        license.buttons[XCUIIdentifierCloseWindow].click()
        about.buttons["使用帮助"].click()
        let help = app.windows["轻程帮助"]
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        XCTAssertTrue(help.staticTexts["让后台应用少占资源"].exists)
        help.buttons[XCUIIdentifierCloseWindow].click()
        about.buttons[XCUIIdentifierCloseWindow].click()
        settings.buttons[XCUIIdentifierCloseWindow].click()
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
        app.windows["轻程"].buttons[XCUIIdentifierCloseWindow].click()
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
        // Launch Services completion can precede applicationShouldHandleReopen.
        let restored = expectation(for: NSPredicate { _, _ in running?.activationPolicy == .regular },
                                   evaluatedWith: nil)
        wait(for: [restored], timeout: 5)
        XCTAssertEqual(running?.activationPolicy, .regular)
        app.activate()
        XCTAssertTrue(app.windows["轻程"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.matching(identifier: "轻程").count, 1)
    }
    /// 使用无持久数据的界面夹具验证取消与退出，保留本机用户配置。
    func testEraseDataConfirmationAndQuit() throws {
        let app = launchFixture()
        defer { if app.state != .notRunning { app.terminate() } }
        app.windows["轻程"].buttons["open-settings"].click()
        let settings = app.windows["轻程设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.buttons["erase-app-data"].click()
        XCTAssertTrue(settings.sheets.buttons["取消"].waitForExistence(timeout: 5))
        settings.sheets.buttons["取消"].click()
        XCTAssertTrue(settings.exists)
        settings.buttons["erase-app-data"].click()
        settings.sheets.buttons["清除并退出"].click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
    }

    /// 界面夹具不发送统计，验证默认开启和关于窗口内的开关变化。
    func testUsageAnalyticsConsentToggle() throws {
        let app = launchFixture()
        defer { app.terminate() }
        app.windows["轻程"].buttons["open-settings"].click()
        app.windows["轻程设置"].buttons["关于轻程"].click()
        let about = app.windows["关于轻程"]
        XCTAssertTrue(about.buttons["open-usage-statistics"].waitForExistence(timeout: 5))
        XCTAssertTrue(about.descendants(matching: .any).matching(identifier: "project-issues").firstMatch.exists)
        about.buttons["open-usage-statistics"].click()
        let statistics = app.windows["使用统计"]
        let toggle = statistics.switches["usage-analytics-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 1)
        toggle.click()
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 0)
        XCTAssertTrue(statistics.staticTexts["默认开启匿名使用统计，收集系统地区、版本等使用概况，不包含姓名、文件或其他应用明细。"].exists)
        XCTAssertTrue(statistics.staticTexts["台设备在用轻程"].exists)
        toggle.click()
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 1)
        XCTAssertGreaterThanOrEqual(statistics.frame.width, 580)
    }

    /// 展开标题是完整按钮，文字和箭头共享相同的交互入口。
    func testProcessInformationHeaderExpandsOnTextClick() throws {
        let app = launchFixture()
        defer { app.terminate() }
        let window = app.windows["轻程"]
        window.staticTexts["网页浏览器"].firstMatch.click()
        let header = window.disclosureTriangles["应用与进程信息"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertFalse(window.staticTexts["example.browser"].exists)
        // 点击标题区域，避开左端箭头，证明整行可以切换。
        header.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).click()
        XCTAssertTrue(window.staticTexts["example.browser"].waitForExistence(timeout: 5))
        header.click()
        XCTAssertFalse(window.staticTexts["example.browser"].exists)
    }

    /// 验证网络配置进入已配置列表，同时明确显示待启用状态。
    func testNetworkRuleDraftAndConfiguredList() throws {
        let app = launchFixture()
        defer { app.terminate() }
        let window = app.windows["轻程"]
        window.staticTexts["网页浏览器"].firstMatch.click()
        XCTAssertFalse(window.popUpButtons["network-rule-mode"].exists)
        window.buttons["open-settings"].click()
        let settings = app.windows["轻程设置"]
        let experiment = settings.checkBoxes["network-features-enabled"]
        XCTAssertTrue(experiment.waitForExistence(timeout: 5))
        XCTAssertEqual((experiment.value as? NSNumber)?.intValue, 0)
        experiment.click()
        settings.buttons[XCUIIdentifierCloseWindow].click()
        let mode = window.popUpButtons["network-rule-mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.click()
        app.menuItems["限制速度"].click()
        XCTAssertTrue(window.textFields["network-download-limit"].waitForExistence(timeout: 5))
        XCTAssertTrue(window.staticTexts["测试功能未实现"].exists)
        XCTAssertFalse(window.switches["management-toggle"].isEnabled)
        let scope = window.popUpButtons["network-rule-scope"]
        scope.click()
        app.menuItems["始终"].click()
        window.descendants(matching: .any).matching(identifier: "已配置规则").firstMatch.click()
        XCTAssertTrue(window.staticTexts["网页浏览器"].exists)
        window.buttons["remove-network-rule"].click()
        XCTAssertTrue(window.staticTexts["还没有后台规则"].waitForExistence(timeout: 5))
    }

}
