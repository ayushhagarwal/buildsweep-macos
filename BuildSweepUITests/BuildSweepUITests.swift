import XCTest

final class BuildSweepUITests: XCTestCase {
    func testLaunchShowsOnboardingOrOverview() {
        let app = XCUIApplication()
        app.launch()
        let onboarding = app.staticTexts["Understand Xcode storage"]
        let overview = app.staticTexts["Xcode storage at a glance"]
        XCTAssertTrue(onboarding.waitForExistence(timeout: 5) || overview.waitForExistence(timeout: 2))
    }
}

