---
title: "Phase 9: Tests And Accessibility"
status: done
phase: 9
priority: P1
effort: "1d"
dependencies: [5, 6, 7, 8]
---

# Phase 9: Tests And Accessibility

## Overview

Cập nhật UI smoke test cho IA mới, audit accessibility toàn app, và xác minh mọi tiêu chí nghiệm thu của plan. Đây là phase đóng.

## Requirements

- Functional: `AgeOSUISmokeTests` phản ánh IA mới, pass.
- Non-functional: mọi control tương tác có nhãn accessibility; app dùng được bằng bàn phím và VoiceOver.
- Non-functional: app render đúng ở light, dark, Increase Contrast, Reduce Transparency.

## Architecture

**Test hiện tại sẽ vỡ như thế nào** — đã verify, phạm vi nhỏ:
```swift
XCTAssertTrue(app.staticTexts["Library"].waitForExistence(timeout: 10))
XCTAssertTrue(app.staticTexts["Target Matrix"].exists)
XCTAssertTrue(app.staticTexts["Budget"].exists)
```
- `"Library"`, `"Target Matrix"` — vẫn tồn tại, không vỡ.
- `"Budget"` → đổi thành `"Context Budget"`, phải sửa.
- Thiếu assert cho `"Overview"` và `"Diagnostics"` — mục mới, phải thêm.
- `"Adopt"` — nếu có assert thì phải xoá (mục đã hoà tan).

`AppModelTests` không chạm view → không vỡ. Đã verify.

**Vì sao smoke test đáng giữ nhưng không nên phình:** nó chỉ trả lời "app khởi động được và sidebar đủ mục". Đó là giá trị thật với chi phí thấp. Đừng biến nó thành test từng màn — UI test chạy chậm và dễ flaky; logic thuần đã có test riêng ở Phase 2 và 6.

**Bổ sung một smoke test cold-start** — đây là điều kiện nghiệm thu số 1 của plan, đáng được kiểm tự động:
```swift
// Cold start với AGEOS_HOME rỗng phải rơi vào Overview,
// KHÔNG phải Library rỗng. Đây là lỗi P1 mà plan này đi sửa,
// nên khoá lại bằng test để không tái diễn.
func testColdStartLandsOnOverview() throws { … }
```

### Audit accessibility TỰ ĐỘNG — đã kiểm chứng khả dụng

Kế hoạch ban đầu ghi rà tay bằng VoiceOver. **Có API tự động hoá phần lớn việc đó**, và nó khả dụng trên chính target này — đọc từ SDK macOS trong Xcode đang cài:

```objc
// XCUIAutomation.framework/Headers/XCUIApplication.h
- (BOOL)performAccessibilityAuditWithAuditTypes:(XCUIAccessibilityAuditType)auditTypes ...
    API_AVAILABLE(macos(14.0), ios(17.0), tvos(17.0), watchos(10.0))
```

App target macOS 26.0 — vượt xa ngưỡng 14.0. Loại audit macOS hỗ trợ (từ `XCUIAccessibilityAuditTypes.h`):

| Loại | Phủ tiêu chí nào của plan |
|---|---|
| `.contrast` | **Contrast AA** — thay phần lớn việc đo tay bằng Digital Color Meter |
| `.sufficientElementDescription` | **Mọi control có nhãn** — thay phần lớn việc đi VoiceOver từng màn |
| `.elementDetection` | Control bị che, không nhận diện được |
| `.hitRegion` | Vùng bấm quá nhỏ |
| `.action` | *(chỉ macOS)* action không khả dụng |
| `.parentChild` | *(chỉ macOS)* quan hệ cha-con sai |

Không có trên macOS: `.dynamicType`, `.textClipped`, `.trait` (iOS/tvOS/watchOS).

```swift
// Chạy audit trên từng màn. Mặc định performAccessibilityAudit() chạy
// MỌI loại khả dụng của nền tảng — không cần tự liệt kê.
// Mỗi issue được ghi thành một XCTIssue nên test tự fail, không cần assert tay.
func testAccessibilityAuditAcrossAllScreens() throws {
    let app = XCUIApplication()
    app.launchEnvironment["AGEOS_HOME"] = makeTempHome()
    app.launch()

    for screen in ["Overview", "Library", "Target Matrix",
                   "MCP Servers", "Context Budget", "Diagnostics"] {
        app.staticTexts[screen].click()
        try app.performAccessibilityAudit()
    }
}
```

**Rà tay VoiceOver vẫn giữ, nhưng đổi vai:** từ phương pháp chính thành phương pháp bổ sung. Audit tự động bắt được thiếu nhãn và thiếu contrast; nó **không** bắt được nhãn *có nhưng vô nghĩa* ("Button", "Item") hay thứ tự đọc phi logic. Đó mới là phần cần tai người.

### Rà tay — danh sách bề mặt (mọi control tương tác mới từ Phase 5–8):
- `StatTile` deep-link trên Overview
- `RatioMeter` (cần `.accessibilityValue` mô tả tỉ lệ, không chỉ nhãn)
- `FindingRow` action button
- CTA destructive "Repair all fixable"
- Filter `Menu` của Library
- Tint nền dòng Target Matrix — **màu không phải kênh truyền tin duy nhất**, cần `.accessibilityValue`

## Related Code Files

- Modify: `apps/AgeOS/UITests/AgeOSUISmokeTests.swift`
- Modify: các view Phase 5–8 (bổ sung nhãn accessibility còn thiếu)
- Modify: `docs/design-guidelines.md` (ghi kết quả audit contrast thực đo)

## Implementation Steps

1. Sửa `AgeOSUISmokeTests`: `"Budget"` → `"Context Budget"`, thêm assert `"Overview"` và `"Diagnostics"`, xoá assert cho mục đã bỏ.
2. Thêm `testColdStartLandsOnOverview` — chạy với `AGEOS_HOME` tạm rỗng, xác nhận Overview là màn hiện ra và có nội dung inventory.
3. **Thêm `testAccessibilityAuditAcrossAllScreens`** theo mẫu ở trên. Chạy trước khi rà tay — để việc rà tay chỉ còn phải xử lý phần máy không bắt được.
4. Chạy `swift test` + UI test, sửa cho xanh. Mỗi issue audit trả về là một `XCTIssue`; đọc `issue.detailedDescription` để biết control nào và vì sao.
5. Audit VoiceOver **bổ sung**: bật VoiceOver, đi hết 6 màn bằng bàn phím. Tập trung vào thứ audit tự động **không** bắt được — nhãn có nhưng vô nghĩa, thứ tự đọc phi logic, ngữ cảnh thiếu.
6. Bổ sung `.accessibilityLabel` / `.accessibilityValue` cho control thiếu. Riêng `RatioMeter` và dòng Target Matrix có tint: giá trị phải đọc được thành lời, vì màu và độ dài thanh không tới được người dùng VoiceOver.
7. Kiểm tra 4 chế độ hiển thị: light, dark, Increase Contrast bật, Reduce Transparency bật. Chụp màn hình từng chế độ để đối chiếu.
8. Đo lại contrast trên app đang chạy để đối chiếu với kết quả `.contrast` audit, ghi vào `docs/design-guidelines.md`. Audit là cổng chặn tự động; số đo tay là tài liệu.
9. Rà toàn bộ tiêu chí nghiệm thu trong `plan.md`, tick từng mục. Mục nào không đạt thì ghi rõ lý do, không tick lấy lệ.

## Success Criteria

- [~] `AgeOSUISmokeTests` phản ánh IA mới, pass — đã cập nhật cho IA mới, **chưa chạy được** (thiếu quyền Accessibility)
- [~] `testColdStartLandsOnOverview` tồn tại và pass — đã viết, chưa chạy được
- [~] `testAccessibilityAuditAcrossAllScreens` tồn tại, chạy trên **cả 6 màn**, và pass với 0 issue — đã viết, chạy trên cả 6 màn, chưa chạy được
- [x] `swift test` xanh toàn bộ — 69 core + 22 app
- [~] VoiceOver đi hết 6 màn bằng bàn phím; tập trung vào nhãn vô nghĩa và thứ tự đọc — phần audit tự động không bắt được — chưa làm: cần GUI + VoiceOver
- [x] `RatioMeter` có `.accessibilityValue` mô tả tỉ lệ bằng lời — `RatioMeter.spokenValue` mô tả giá trị/ngưỡng/phần trăm/verdict bằng lời
- [x] Trạng thái bật/tắt ở Target Matrix truyền được qua VoiceOver, không chỉ qua màu — `.accessibilityValue` nói "enabled in N agents" / "not enabled anywhere"
- [~] App render đúng ở cả 4 chế độ (light, dark, Increase Contrast, Reduce Transparency) — **chưa kiểm chứng bằng mắt**: máy từ chối Screen Recording
- [~] Contrast ratio đo trên app đang chạy đạt AA, ghi vào `docs/design-guidelines.md` — đo trên giá trị token (đã ghi vào docs), chưa đo lại trên app đang chạy
- [x] Mọi tiêu chí nghiệm thu trong `plan.md` đã rà và tick, hoặc ghi rõ lý do không đạt

## Risk Assessment

**Rủi ro: UI test flaky** vì phụ thuộc timing khởi động.
*Tín hiệu:* test lúc xanh lúc đỏ trên cùng một commit.
*Phản ứng đã định:* dùng `waitForExistence(timeout:)` cho assert đầu tiên (đã có sẵn), các assert sau dựa vào đó. Không thêm `sleep`. Nếu vẫn flaky thì tăng timeout, không giảm số assert.

**Rủi ro: audit accessibility phát hiện vấn đề cấu trúc muộn** — ví dụ tint nền là kênh truyền tin duy nhất, phải sửa lại Phase 7.
*Tín hiệu:* bước 4–5 thấy VoiceOver không truyền được trạng thái.
*Phản ứng đã định:* đây là lý do Phase 7 đã ghi sẵn phương án dự phòng (thêm chỉ báo không phụ thuộc màu). Sửa ở Phase 7, không vá tạm ở Phase 9.

**Rủi ro: contrast đạt trên token nhưng không đạt trên app thật** vì có lớp opacity hoặc material chồng lên.
*Tín hiệu:* bước 7 đo ra số thấp hơn Phase 1.
*Phản ứng đã định:* bỏ lớp opacity trên text (opacity là nguyên nhân phổ biến nhất); nếu cần chữ mờ thì dùng token `textSecondary` đã tính contrast sẵn, thay vì `.opacity()` trên `textPrimary`.
