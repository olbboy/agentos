import XCTest

/// UI smoke: app khởi động được, sidebar đủ mục, không crash.
///
/// Giữ XCTest chứ không đổi sang swift-testing: `XCUIApplication` và
/// `performAccessibilityAudit` là API họ XCTest, swift-testing không có bản
/// tương đương. Unit test mới thì ngược lại — dùng swift-testing.
///
/// Đừng để file này phình thành test từng màn: UI test chạy chậm và dễ flaky.
/// Logic thuần đã có test riêng ở `DesignSystemTests` và `DiagnosticSeverityTests`.
final class AgeOSUISmokeTests: XCTestCase {

    /// Home tạm cho mỗi lần chạy — test không bao giờ đụng `~/.ageos` thật.
    private func makeTempHome() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ageos-ui-smoke-\(UUID().uuidString.prefix(6))").path
    }

    private func launch(home: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AGEOS_HOME"] = home
        app.launch()
        return app
    }

    func testLaunchShowsSidebar() throws {
        let tmp = makeTempHome()
        let app = launch(home: tmp)
        defer {
            app.terminate()
            try? FileManager.default.removeItem(atPath: tmp)
        }

        XCTAssertTrue(app.staticTexts["Overview"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Library"].exists)
        XCTAssertTrue(app.staticTexts["Target Matrix"].exists)
        XCTAssertTrue(app.staticTexts["MCP Servers"].exists)
        XCTAssertTrue(app.staticTexts["Context Budget"].exists)
        XCTAssertTrue(app.staticTexts["Diagnostics"].exists)

        // Hai mục đã hoà tan vào Overview và Diagnostics — còn sót nghĩa là
        // IA cũ chưa được gỡ hết.
        XCTAssertFalse(app.staticTexts["Adopt"].exists)
        XCTAssertFalse(app.staticTexts["Scan"].exists)
    }

    /// Điều kiện nghiệm thu số 1 của bản redesign, nên khoá bằng test.
    ///
    /// Lỗi đang đi sửa: mở app lần đầu rơi vào Library RỖNG — màn hình trắng, không
    /// biết làm gì tiếp. Overview phải hiện ngay inventory quét từ máy thật, kể cả
    /// khi `AGEOS_HOME` hoàn toàn trắng, vì `EffectiveLoadScanner` đọc thư mục agent
    /// chứ không đọc `~/.ageos`.
    func testColdStartLandsOnOverview() throws {
        let tmp = makeTempHome()
        let app = launch(home: tmp)
        defer {
            app.terminate()
            try? FileManager.default.removeItem(atPath: tmp)
        }

        XCTAssertTrue(app.staticTexts["Overview"].waitForExistence(timeout: 10))

        // Cold-start hero chỉ hiện khi library rỗng — đúng tình huống này.
        XCTAssertTrue(app.staticTexts["Start here"].waitForExistence(timeout: 10),
                      "Library rỗng phải hiện cold-start hero, không phải màn trắng")

        // Có nội dung thật, không phải khung chờ: nút import chỉ bật khi inventory
        // đã được điền.
        // Chờ nút ENABLE, không chỉ chờ nó tồn tại. Nút disabled vẫn "tồn tại" ngay
        // lúc render đầu tiên, trước khi quét xong trên Task.detached — assert
        // `isEnabled` ngay sau `waitForExistence` sẽ fail giả trên máy chậm.
        let importButton = app.buttons["Import into library"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 15))
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"),
                                  evaluatedWith: importButton)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 20), .completed,
                       "Inventory phải có dữ liệu máy thật ngay cả khi AGEOS_HOME trắng")

        XCTAssertTrue(app.buttons["Add a source"].exists)
    }

    /// Audit accessibility tự động trên cả 6 màn.
    ///
    /// `performAccessibilityAudit()` mặc định chạy MỌI loại audit khả dụng của nền
    /// tảng — trên macOS gồm `.contrast`, `.sufficientElementDescription`,
    /// `.elementDetection`, `.hitRegion`, `.action`, `.parentChild`. Mỗi vấn đề tìm
    /// được trở thành một `XCTIssue`, nên test tự fail, không cần assert tay.
    ///
    /// Nó KHÔNG thay được tai người: audit bắt được thiếu nhãn và thiếu contrast,
    /// nhưng không bắt được nhãn *có mà vô nghĩa* ("Button", "Item") hay thứ tự đọc
    /// phi logic. Rà tay VoiceOver vẫn cần, chỉ là để dành cho đúng phần đó.
    func testAccessibilityAuditAcrossAllScreens() throws {
        let tmp = makeTempHome()
        let app = launch(home: tmp)
        defer {
            app.terminate()
            try? FileManager.default.removeItem(atPath: tmp)
        }

        XCTAssertTrue(app.staticTexts["Overview"].waitForExistence(timeout: 10))

        for screen in ["Overview", "Library", "Target Matrix",
                       "MCP Servers", "Context Budget", "Diagnostics"] {
            let item = app.staticTexts[screen]
            XCTAssertTrue(item.waitForExistence(timeout: 10), "Không thấy mục sidebar '\(screen)'")
            item.click()

            // Chờ detail pane thật sự đổi trước khi audit. Không có bước này, audit
            // có thể chạy trên cây accessibility của màn TRƯỚC — nếu màn trước sạch
            // thì test báo pass cho màn hiện tại dù chưa từng kiểm nó. False-pass
            // đúng nghĩa: nó che mất lỗi accessibility thật.
            let title = app.staticTexts.matching(identifier: screen).element(boundBy: 1)
            _ = title.waitForExistence(timeout: 10)

            XCTContext.runActivity(named: "Accessibility audit: \(screen)") { _ in
                do {
                    try app.performAccessibilityAudit()
                } catch {
                    XCTFail("Audit thất bại trên màn \(screen): \(error)")
                }
            }
        }
    }
}
