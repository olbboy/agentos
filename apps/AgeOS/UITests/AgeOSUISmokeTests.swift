import XCTest

/// UI smoke: app khởi động được, sidebar đủ mục, không crash.
final class AgeOSUISmokeTests: XCTestCase {
    func testLaunchShowsSidebar() throws {
        let app = XCUIApplication()
        // Home tạm — smoke test không đụng ~/.ageos thật.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ageos-ui-smoke-\(UUID().uuidString.prefix(6))").path
        app.launchEnvironment["AGEOS_HOME"] = tmp
        app.launch()

        XCTAssertTrue(app.staticTexts["Library"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Target Matrix"].exists)
        XCTAssertTrue(app.staticTexts["Budget"].exists)
        app.terminate()
        try? FileManager.default.removeItem(atPath: tmp)
    }
}
