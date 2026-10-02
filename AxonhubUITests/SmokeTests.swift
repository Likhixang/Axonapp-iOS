import XCTest

final class SmokeTests: XCTestCase {
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testReadmeScreenshots() {
        for language in ["zh-Hans", "en"] {
            let english = language == "en"
            let app = XCUIApplication()
            app.launchArguments += ["--readme-preview", "-AppleLanguages", "(\(language))",
                                    "-AppleLocale", english ? "en_US" : "zh_CN",
                                    "-appAppearance", "light"]
            app.launch()
            XCTAssertTrue(app.staticTexts["3.8M"].waitForExistence(timeout: 30))
            XCTAssertTrue(app.staticTexts[english ? "Recent trend" : "近期趋势"].exists)
            XCTAssertTrue(app.navigationBars[english ? "Dashboard" : "仪表盘"].exists)
            // The last dashboard query completes before taking the screenshot.
            let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 0"), object: app.progressIndicators)
            XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 30), .completed)
            capture(app, "README-\(language)-dashboard")
            app.tabBars.buttons[english ? "Gateway" : "网关"].tap()
            app.buttons[english ? "Channels" : "渠道"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["OpenAI"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts["Anthropic"].exists)
            capture(app, "README-\(language)-channels")
            app.navigationBars.buttons.firstMatch.tap()
            app.buttons[english ? "Models" : "模型"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["GPT-4.1"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts["Claude Sonnet 4"].exists)
            capture(app, "README-\(language)-models")
            app.terminate()
        }
    }
}
