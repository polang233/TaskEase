import XCTest

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
