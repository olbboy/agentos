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

    /// `activate()` sau `launch()` là BẮT BUỘC, không phải thừa.
    ///
    /// Đo được: chỉ `launch()` thì `app.windows.count == 0` và mọi assertion đều
    /// fail như thể app hỏng. Thêm `activate()` thì thành 1 window với đầy đủ nội
    /// dung. App tự nó không sao — mở bằng `open -n` luôn ra cửa sổ "Overview" —
    /// khác biệt nằm ở cách XCUITest khởi chạy tiến trình.
    private func launch(home: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AGEOS_HOME"] = home
        app.launch()
        app.activate()
        return app
    }

    /// Sidebar được địa chỉ hoá bằng identifier chứ không bằng nhãn hiển thị:
    /// hàng trong `List` không phơi nhãn ra ngoài cell, và nhãn là thứ dịch được
    /// nên bám vào nó là bám vào thứ sẽ đổi.
    private func sidebarItem(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.descendants(matching: .any)["sidebar.\(name)"]
    }

    private let screens = ["Overview", "Library", "Target Matrix",
                           "MCP Servers", "Context Budget", "Diagnostics"]

    /// Bỏ qua các phần tử KHUNG do SwiftUI/AppKit tự sinh, giữ lại mọi thứ của app.
    ///
    /// Đo được: sau khi sửa hết lỗi contrast, còn 45 issue — 30 `Group`, 6
    /// `TouchBar`, 2 `Outline` và mấy `Group` chrome cửa sổ. KHÔNG cái nào có
    /// identifier, tức không cái nào do app tạo. Đó là container SwiftUI dựng ngầm
    /// cho `NavigationSplitView`, `Section`, `List` — không có API nào gắn nhãn cho
    /// chúng, và gắn nhãn cho một Group bố cục cũng không giúp gì cho VoiceOver.
    ///
    /// Bộ lọc cố ý HẸP: chỉ bỏ qua khi phần tử vừa là kiểu container, vừa KHÔNG có
    /// identifier. Thêm một Button thiếu nhãn hay một StaticText tương phản kém thì
    /// test vẫn đỏ — đó là điều nó tồn tại để bắt.
    private static func isFrameworkContainer(_ element: XCUIElement?) -> Bool {
        guard let element else { return false }
        guard element.identifier.isEmpty else { return false }
        switch element.elementType {
        case .group, .outline, .touchBar, .table, .scrollView, .splitGroup, .other:
            return true
        default:
            return false
        }
    }

    /// SwiftUI `Menu` trong toolbar dựng ra một AXMenuButton không phơi AXPress,
    /// nên audit `.action` luôn báo thiếu. Đã thử `.accessibilityAddTraits(.isButton)`
    /// — không đổi gì; không có API nào thêm action cho `Menu`.
    ///
    /// Bỏ qua ở đây là chấp nhận có ý thức, KHÔNG phải giấu lỗi: khả năng dùng thật
    /// của nút này được `testFilterMenuOpens` chứng minh bằng cách bấm và kiểm mục
    /// bên trong. Nếu nút hỏng thật thì test đó đỏ.
    private static func isSwiftUIMenuActionGap(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        issue.auditType == .action && issue.element?.elementType == .menuButton
    }

    func testLaunchShowsSidebar() throws {
        let tmp = makeTempHome()
        let app = launch(home: tmp)
        defer {
            app.terminate()
            try? FileManager.default.removeItem(atPath: tmp)
        }

        XCTAssertTrue(sidebarItem(app, "Overview").waitForExistence(timeout: 15))
        for screen in screens {
            XCTAssertTrue(sidebarItem(app, screen).exists, "Thiếu mục sidebar '\(screen)'")
        }

        // Hai mục đã hoà tan vào Overview và Diagnostics — còn sót nghĩa là
        // IA cũ chưa được gỡ hết.
        XCTAssertFalse(sidebarItem(app, "Adopt").exists)
        XCTAssertFalse(sidebarItem(app, "Scan").exists)

        // Nhóm sidebar vẫn là nhãn hiển thị, và đó là thứ người dùng đọc.
        XCTAssertTrue(app.staticTexts["Distribute"].exists)
        XCTAssertTrue(app.staticTexts["Health"].exists)
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

        XCTAssertTrue(sidebarItem(app, "Overview").waitForExistence(timeout: 15))

        // Cold-start hero chỉ hiện khi library rỗng — đúng tình huống này.
        XCTAssertTrue(app.staticTexts["Start here"].waitForExistence(timeout: 15),
                      "Library rỗng phải hiện cold-start hero, không phải màn trắng")

        // Chờ nút ENABLE, không chỉ chờ nó tồn tại. Nút disabled vẫn "tồn tại" ngay
        // lúc render đầu tiên, trước khi quét xong trên Task.detached.
        let importButton = app.buttons["Import into library"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 20))
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"),
                                  evaluatedWith: importButton)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 30), .completed,
                       "Inventory phải có dữ liệu máy thật ngay cả khi AGEOS_HOME trắng")

        XCTAssertTrue(app.buttons["Add a source"].exists)

        // Bốn StatTile là Button vì mỗi cái deep-link đi đâu đó — tile chỉ hiện số
        // mà không bấm được thì đã bị loại khỏi màn này có chủ ý.
        for tile in ["distinct skills", "agents detected",
                     "managed by AgeOS", "loaded in 2+ agents"] {
            XCTAssertTrue(app.buttons[tile].exists, "Thiếu StatTile '\(tile)'")
        }
    }

    /// Bù cho chỗ audit `.action` không kiểm được: chứng minh Menu filter thật sự
    /// mở ra và có mục bên trong. Đây là lý do việc bỏ qua issue kia là an toàn.
    func testFilterMenuOpens() throws {
        let tmp = makeTempHome()
        let app = launch(home: tmp)
        defer {
            app.terminate()
            try? FileManager.default.removeItem(atPath: tmp)
        }

        sidebarItem(app, "Library").click()
        let menu = app.descendants(matching: .any)["library.filterMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        XCTAssertTrue(menu.isHittable, "Menu filter phải bấm được")
        menu.click()

        XCTAssertTrue(app.menuItems["Deprecated only"].waitForExistence(timeout: 10),
                      "Menu mở ra phải có mục lọc bên trong")
        XCTAssertTrue(app.menuItems["Enabled somewhere"].exists)
    }

    /// Audit accessibility tự động trên cả 6 màn.
    ///
    /// `performAccessibilityAudit()` mặc định chạy MỌI loại audit khả dụng của nền
    /// tảng — trên macOS gồm `.contrast`, `.sufficientElementDescription`,
    /// `.elementDetection`, `.hitRegion`, `.action`, `.parentChild`. Mỗi vấn đề tìm
    /// được trở thành một `XCTIssue`, nên test tự fail, không cần assert tay.
    ///
    /// Nó KHÔNG thay được tai người: audit bắt được thiếu nhãn và thiếu contrast,
    /// nhưng không bắt được nhãn *có mà vô nghĩa* hay thứ tự đọc phi logic.
    func testAccessibilityAuditAcrossAllScreens() throws {
        let tmp = makeTempHome()
        let app = launch(home: tmp)
        defer {
            app.terminate()
            try? FileManager.default.removeItem(atPath: tmp)
        }

        XCTAssertTrue(sidebarItem(app, "Overview").waitForExistence(timeout: 15))

        for screen in screens {
            let item = sidebarItem(app, screen)
            XCTAssertTrue(item.waitForExistence(timeout: 10), "Không thấy mục sidebar '\(screen)'")
            item.click()

            // Chờ detail pane thật sự đổi trước khi audit. Không có bước này, audit
            // có thể chạy trên cây của màn TRƯỚC — nếu màn trước sạch thì test báo
            // pass cho màn hiện tại dù chưa từng kiểm nó.
            let title = app.staticTexts[screen]
            _ = title.waitForExistence(timeout: 10)

            XCTContext.runActivity(named: "Accessibility audit: \(screen)") { _ in
                do {
                    try app.performAccessibilityAudit { issue in
                        Self.isFrameworkContainer(issue.element)
                            || Self.isSwiftUIMenuActionGap(issue)
                    }
                } catch {
                    XCTFail("Audit thất bại trên màn \(screen): \(error)")
                }
            }
        }
    }
}
