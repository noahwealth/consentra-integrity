import XCTest

/// Walks the demo path against a running server (start it with fresh state first).
/// Set TEST_RUNNER_SCREENSHOT_DIR to save PNGs of each step.
final class DemoFlowUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
    }

    private func snap(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else { return }
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testConnectShareAndPresent() {
        // Connect (Figma 22–25), only if not already connected.
        if app.buttons["home.connect"].waitForExistence(timeout: 5) {
            app.buttons["home.connect"].tap()
            app.buttons["connect.thameside"].tap()
            snap("02-signin")
            app.buttons["Sign in"].tap()
            XCTAssertTrue(app.buttons["Allow"].waitForExistence(timeout: 5))
            snap("03-authorize")
            app.buttons["Allow"].tap()
            XCTAssertTrue(app.staticTexts["Thameside General connected"].waitForExistence(timeout: 5))
            snap("04-connected")
            app.buttons["Done"].tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["home.source"].waitForExistence(timeout: 5))
        snap("05-home")

        // Share (Figma 18) → builder → present (Figma 19).
        app.tabBars.buttons["Share"].tap()
        app.buttons["share.provider"].tap()
        XCTAssertFalse(app.buttons["Create Share"].isEnabled, "must not share with nothing selected")
        app.buttons["category.allergies"].tap()
        app.buttons["category.labs"].tap()
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("Dr. Rivera, Mass General\n")
        snap("06-builder")
        XCTAssertTrue(app.buttons["Create Share"].isEnabled)
        app.buttons["Create Share"].tap()
        XCTAssertTrue(app.staticTexts["Present to Provider"].waitForExistence(timeout: 5))
        sleep(1)
        snap("07-present")

        // Signed pass → Wallet's own add sheet.
        app.buttons["Add to Apple Wallet"].firstMatch.tap()
        sleep(4)
        snap("08-wallet-sheet")
    }

    /// Run after testConnectShareAndPresent with a "clinician" polling active links (see README).
    func testRevokeFromManageAccess() {
        app.tabBars.buttons["Passport"].tap()
        app.buttons["home.manageAccess"].tap()
        let row = app.buttons["access.row.active"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        snap("09-access-list")
        row.tap()
        XCTAssertTrue(app.staticTexts["Opened on iPhone"].firstMatch.waitForExistence(timeout: 15), "clinician view should appear live")
        snap("10-access-detail")
        let revoke = app.buttons["access.revoke"]
        for _ in 0..<4 where !(revoke.exists && revoke.isHittable) { app.swipeUp() }
        revoke.tap()
        let confirm = app.sheets.buttons["Revoke Access"].firstMatch.exists ? app.sheets.buttons["Revoke Access"].firstMatch : app.buttons["Revoke Access"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        snap("11-revoke-confirm")
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Revoked"].firstMatch.waitForExistence(timeout: 5))
        snap("12-revoked")
        app.tabBars.buttons["Activity"].tap()
        sleep(1)
        snap("13-activity")
    }
}
