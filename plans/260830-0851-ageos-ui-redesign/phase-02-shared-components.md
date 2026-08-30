---
title: "Phase 2: Shared Components"
status: done
phase: 2
priority: P1
effort: "1.5d"
dependencies: [1]
---

# Phase 2: Shared Components

## Overview

Dựng 5 component dùng chung trên token layer của Phase 1. Chúng thay thế toàn bộ code UI ad-hoc đang lặp trong 6 view. Phase này chưa sửa view nào — chỉ tạo component + preview + test.

## Requirements

- Functional: 5 component (`StatTile`, `RatioMeter`, `StatusPill`, `SectionCard`, `FindingRow`) render đúng cho mọi trạng thái đầu vào, kể cả rỗng và tràn.
- Functional: `BudgetMeter.skillTokens` đổi sang `public` để `StatTile`/Library dùng lại công thức thay vì nhân bản.
- Non-functional: mỗi component có `#Preview` phủ light + dark + trạng thái biên.
- Non-functional: component không tự gọi `AppModel` — nhận dữ liệu qua parameter (dễ preview, dễ test, không kéo theo state toàn cục).

## Architecture

**Vì sao component nhận parameter thay vì đọc `@Environment(AppModel.self)`:** component đọc environment sẽ không preview được nếu không dựng cả AppModel, và không test được độc lập. Truyền dữ liệu vào là ranh giới rõ ràng — view cha lấy state, component chỉ lo hiển thị. Đây là tách "container" và "presentational", quy ước phổ biến ở cả SwiftUI lẫn React.

```
apps/AgeOS/Sources/DesignSystem/Components/
├── StatTile.swift
├── RatioMeter.swift
├── StatusPill.swift
├── SectionCard.swift
└── FindingRow.swift
```

**`StatTile`** — con số lớn + nhãn, tuỳ chọn mẫu số. Thay `AdoptView.stat()`.
```swift
struct StatTile: View {
    let value: String
    let label: String
    /// Mẫu số tuỳ chọn — "12 / 20" đọc được hơn "12" đứng một mình.
    var outOf: String? = nil
}
```

**`RatioMeter`** — thanh ngang dùng **chung một thang** giữa các dòng, để so sánh cross-agent có nghĩa. Thay `ProgressView` rời trong BudgetView.
```swift
struct RatioMeter: View {
    let value: Int
    let threshold: Int?      // nil = adapter không khai báo catalogTokensWarn
    var scaleMax: Int        // trục chung do view cha tính, KHÔNG phải threshold riêng
}
```
Điểm mấu chốt: `scaleMax` do view cha truyền vào (thường là `max` của mọi agent, hoặc `max` của mọi threshold). Nếu mỗi meter tự chuẩn hoá theo threshold riêng thì hai thanh dài bằng nhau lại mang giá trị khác nhau — đúng lỗi mà Phase 5 đang đi sửa.
Khi `threshold == nil`: vẫn vẽ thanh theo `scaleMax`, nhưng không tô cảnh báo và hiện nhãn "no threshold set". Đã verify: cả 6 adapter đang ship đều khai báo `catalogTokensWarn` (10000–20000), nên nhánh này chỉ chạm adapter JSON bên thứ ba.

**`StatusPill`** — chip trạng thái. Thay Capsule "deprecated" và `HealthBadge`.
```swift
enum PillTone { case neutral, success, warning, danger, info }
struct StatusPill: View {
    let text: String
    let tone: PillTone
    var icon: String? = nil
}
```

**`SectionCard`** — thay mọi `GroupBox` trần. Header + action tuỳ chọn + nội dung.

**`FindingRow`** — một dòng chẩn đoán: icon severity + `StatusPill` + message + action.
```swift
struct FindingRow: View {
    let severity: PillTone
    let message: String
    /// nil = không có cách sửa tự động; view hiện nhãn "No automatic fix"
    /// thay vì im lặng bỏ trống, để người dùng biết đó là kết luận chứ không phải thiếu sót.
    let action: (title: String, run: () -> Void)?
}
```

## Related Code Files

- Create: `apps/AgeOS/Sources/DesignSystem/Components/StatTile.swift`
- Create: `apps/AgeOS/Sources/DesignSystem/Components/RatioMeter.swift`
- Create: `apps/AgeOS/Sources/DesignSystem/Components/StatusPill.swift`
- Create: `apps/AgeOS/Sources/DesignSystem/Components/SectionCard.swift`
- Create: `apps/AgeOS/Sources/DesignSystem/Components/FindingRow.swift`
- Create: `apps/AgeOS/Tests/DesignSystemTests.swift` — dùng **swift-testing** (`import Testing`, `@Test`, `#expect`), không phải XCTest. Repo đang lệch: `Tests/` (core SPM) dùng swift-testing ở **15 file**, `apps/AgeOS/Tests` + `UITests` dùng XCTest ở **2 file**. Đã kiểm chứng `Testing.framework` có sẵn trong platform macOS của Xcode (cùng thư mục với `XCTest.framework`), nên test bundle do xcodegen sinh `import Testing` được, không cần khai báo thêm trong `project.yml`. Theo quy ước áp đảo của repo. **Ngoại lệ: UI test bắt buộc giữ XCTest** — `XCUIApplication` và `performAccessibilityAudit` là API họ XCTest, swift-testing không có bản tương đương.
- Modify: `Sources/AgeOSCore/intelligence/BudgetMeter.swift` — **dòng 37**, `static func skillTokens(name:description:truncateChars:)`. Cẩn thận: có **hai** ký hiệu cùng tên `skillTokens` trong file này — `public var skillTokens: Int` (dòng 20, property của `Report`, đã public) và `static func` ở dòng 37 (internal, đây mới là cái cần đổi). 3 tham chiếu trong `Tests/AgeOSCoreTests/IntelligenceTests.swift:180,188` và `McpServerLoopbackTests.swift:123` đều trỏ vào **property**, không phải func — không đụng tới.

## Implementation Steps

1. Đổi `static func skillTokens` thành `public static func skillTokens` trong `BudgetMeter.swift`. Đây là ngoại lệ API duy nhất được phép — thêm comment giải thích vì sao public (app dùng lại công thức, tránh drift).
2. Viết 5 component, mỗi file một component, đều lấy giá trị từ token Phase 1.
3. Mỗi component kèm `#Preview` phủ: giá trị bình thường, giá trị 0/rỗng, giá trị tràn (text rất dài, số rất lớn), và cả light lẫn dark.
4. Viết `DesignSystemTests.swift` cho phần có logic thuần: tính tỉ lệ của `RatioMeter` (giá trị vượt `scaleMax` phải clamp, không tràn khỏi khung), map `PillTone` → màu, format mẫu số của `StatTile`.
5. Xác nhận không component nào tham chiếu `AppModel`: `grep -rn "AppModel" apps/AgeOS/Sources/DesignSystem/` phải rỗng.

## Success Criteria

- [x] 5 component tồn tại, đều dùng token Phase 1, không literal spacing/font/color
- [x] `grep -rn "AppModel" apps/AgeOS/Sources/DesignSystem/` trả về rỗng
- [x] Mỗi component có `#Preview` phủ light + dark + trạng thái biên
- [x] `RatioMeter` clamp giá trị vượt `scaleMax`, không vẽ tràn khung
- [x] `RatioMeter` với `threshold == nil` hiện nhãn "no threshold set", không crash
- [x] `FindingRow` với `action == nil` hiện "No automatic fix"
- [x] `BudgetMeter.skillTokens` là `public`, có comment giải thích
- [x] `swift test` xanh

## Risk Assessment

**Rủi ro: `RatioMeter` bị dùng sai — mỗi call site tự truyền `scaleMax` khác nhau.** Khi đó thanh dài bằng nhau lại mang nghĩa khác nhau, tái tạo đúng lỗi đang đi sửa.
*Tín hiệu:* review Phase 5/7 thấy hai `RatioMeter` cạnh nhau có `scaleMax` khác.
*Phản ứng đã định:* bọc thành `RatioMeterGroup` nhận `[value]` và tự tính `scaleMax` một lần, để call site không còn cơ hội truyền sai.

**Rủi ro: đổi `skillTokens` sang public làm rò một API chưa ổn định ra ngoài module.**
*Tín hiệu:* sau này muốn đổi công thức 4-bytes/token mà sợ vỡ consumer.
*Phản ứng đã định:* chấp nhận — đây là app cùng repo, không phải thư viện phát hành. Nếu về sau tách package thì đánh dấu `@_spi` thay vì public.
