---
title: "Phase 1: Design Tokens"
status: done
phase: 1
priority: P1
effort: "1d"
dependencies: []
---

# Phase 1: Design Tokens

## Overview

Dựng lớp token (spacing, radius, type ramp, màu ngữ nghĩa) + Asset Catalog có biến thể light/dark, và ghi `docs/design-guidelines.md`. Đây là nền cho mọi phase UI phía sau.

## Requirements

- Functional: mọi view sau này lấy spacing / font / màu qua token, không literal rời.
- Functional: hướng palette là **gần đơn sắc — màu dành riêng để tải thông tin trạng thái**. Neutral làm nền, accent dùng rất tiết chế, nhận diện đến từ type + spacing.
- Non-functional: palette riêng phải đạt WCAG AA (contrast ≥ 4.5:1 cho body text, ≥ 3:1 cho UI component và text lớn) ở **cả** light và dark.
- Non-functional: hoạt động đúng khi bật Increase Contrast và Reduce Transparency.
- Non-functional: `docs/design-guidelines.md` viết bằng **tiếng Anh** (khớp README và khớp app). 4 file tiếng Việt sẵn có trong `docs/` không đụng tới.

## Architecture

**Nguyên tắc chi phối mọi lựa chọn màu ở phase này:** việc chính của AgeOS là **báo trạng thái** — budget vượt ngưỡng, finding theo severity, adapter verified hay chưa. Nếu màu thương hiệu cạnh tranh với màu trạng thái thì tín hiệu yếu đi. Nên accent phải:

- tách hue rõ khỏi cả `statusSuccess`, `statusWarning`, `statusDanger` (không nằm trong dải xanh lá / vàng cam / đỏ);
- dùng ở diện tích nhỏ: trạng thái active, đường kẻ trái, nhấn dữ liệu nhỏ, eyebrow — **không** làm nền lớn;
- không phải là kênh truyền tin duy nhất ở bất kỳ đâu (xem Phase 7, Phase 9).

Nhận diện thương hiệu đến từ **type ramp + thang spacing + nhịp bố cục**, không đến từ độ bão hoà.

**Vì sao Asset Catalog chứ không phải hằng `Color` trong Swift:** Asset Catalog cho phép khai báo biến thể light/dark **và** High Contrast cho cùng một tên màu. SwiftUI tự chọn biến thể đúng theo môi trường — không cần `@Environment(\.colorScheme)` rải khắp view. Đây là lý do chọn palette riêng vẫn dùng được cơ chế hệ thống.

**Đã kiểm chứng bằng thực nghiệm** (không phải suy đoán): `actool` biên dịch thành công một colorset mang **4 biến thể** cho `--platform macosx --minimum-deployment-target 26.0`, exit 0:

| `appearances` trong `Contents.json` | Khi nào dùng |
|---|---|
| *(không có)* | light, tương phản thường |
| `luminosity: dark` | dark, tương phản thường |
| `contrast: high` | light, **Increase Contrast bật** |
| `luminosity: dark` + `contrast: high` | dark, Increase Contrast bật |

Nên mỗi color set khai báo **4 biến thể, không phải 2**. Đây chính là cách xử lý rủi ro Increase Contrast ở cuối file — hệ thống lo việc chọn, ta chỉ cần khai báo đủ.

**Cũng đã kiểm chứng:** đặt `Assets.xcassets` bên trong `Sources/` thì xcodegen tự đưa vào `PBXResourcesBuildPhase` (`Assets.xcassets in Resources`) — **không cần sửa `project.yml`**.

Ba nhóm token, một file mỗi nhóm để tránh một file khổng lồ:

```
apps/AgeOS/Sources/DesignSystem/
├── Spacing.swift      // thang 4pt + radius
├── Typography.swift   // type ramp
└── Palette.swift      // cầu nối tên màu -> Asset Catalog
apps/AgeOS/Sources/Assets.xcassets/   // color sets, mỗi set 4 biến thể (bảng ở trên)
```

Đặt `Assets.xcassets` **bên trong** `Sources/` vì `project.yml` khai báo `sources: - Sources`; xcodegen tự nhận `.xcassets` là resource. Không cần sửa `project.yml` — nhưng phải xác minh bằng một lần generate + compile.

Ví dụ hình dạng token (không phải giá trị cuối — giá trị chốt ở bước 1):

```swift
// Spacing.swift — thang 4pt. Dùng enum không case để làm namespace,
// không ai lỡ tạo instance được.
enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
}
```

```swift
// Palette.swift — tên ngữ nghĩa, không tên màu.
// "danger" mô tả VAI TRÒ; đổi hue sau này không phải sửa call site.
extension Color {
    static let surface        = Color("surface")
    static let surfaceRaised  = Color("surfaceRaised")
    static let borderSubtle   = Color("borderSubtle")
    static let textPrimary    = Color("textPrimary")
    static let textSecondary  = Color("textSecondary")
    static let accentBrand    = Color("accentBrand")
    static let statusSuccess  = Color("statusSuccess")
    static let statusWarning  = Color("statusWarning")
    static let statusDanger   = Color("statusDanger")
    static let statusInfo     = Color("statusInfo")
}
```

```swift
// Typography.swift — mọi con số dùng monospacedDigit để cột số không nhảy
// khi giá trị đổi (vd meter cập nhật realtime).
extension Font {
    static let displayL = Font.system(size: 28, weight: .semibold)
    static let titleL   = Font.system(size: 20, weight: .semibold)
    static let headline = Font.system(size: 15, weight: .medium)
    static let body     = Font.system(size: 13)
    static let callout  = Font.system(size: 12)
    static let caption  = Font.system(size: 11)
    static let numeric  = Font.system(size: 15, weight: .medium).monospacedDigit()
}
```

## Related Code Files

- Create: `apps/AgeOS/Sources/DesignSystem/Spacing.swift`
- Create: `apps/AgeOS/Sources/DesignSystem/Typography.swift`
- Create: `apps/AgeOS/Sources/DesignSystem/Palette.swift`
- Create: `apps/AgeOS/Sources/Assets.xcassets/` (10 color set, mỗi set có Any Appearance + Dark)
- Create: `docs/design-guidelines.md`
- Verify (có thể không cần sửa): `apps/AgeOS/project.yml`

## Implementation Steps

1. **Chốt giá trị màu cụ thể với user.** Hướng đã chốt ở validate session 1 (gần đơn sắc, màu dành riêng cho trạng thái) — bước này chỉ còn chọn **giá trị** trong hướng đó, không mở lại hướng. Đề xuất một thang neutral + một accent, kèm bảng contrast ratio đo sẵn cho mọi cặp text/nền ở cả light và dark, và **chứng minh accent tách hue khỏi 3 status color**. Không tự chốt hex rồi làm tiếp.
2. Tạo `Assets.xcassets` với 10 color set, **mỗi set đủ 4 biến thể** theo bảng ở phần Architecture. Không phải "cân nhắc" — đã kiểm chứng `actool` chấp nhận, và đây là cách xử lý rủi ro Increase Contrast mà không cần code điều kiện trong view.
3. Viết `Spacing.swift`, `Typography.swift`, `Palette.swift`.
4. Chạy `xcodegen generate` trong `apps/AgeOS/`, mở project, xác nhận `.xcassets` được nhận là resource và `Color("surface")` resolve được (không ra màu hồng fallback).
5. Viết `docs/design-guidelines.md` **bằng tiếng Anh**: bảng token, palette kèm hex + contrast ratio đo được, và quy tắc dùng — accent chỉ cho trạng thái active và nhấn nhỏ; status color không dùng làm nền lớn; màu không bao giờ là kênh truyền tin duy nhất.
6. Đo contrast bằng Digital Color Meter của macOS hoặc script tính tỉ lệ; ghi số thật vào docs, không ghi ước lượng.

## Success Criteria

- [x] Giá trị màu đã được user chốt, không phải agent tự chọn
- [x] Accent tách hue rõ khỏi `statusSuccess` / `statusWarning` / `statusDanger`, có chứng minh
- [x] 10 color set tồn tại, **mỗi set đủ 4 biến thể** (Any / Dark / High Contrast / Dark+High Contrast)
- [x] `xcrun actool Assets.xcassets --compile <tmp> --platform macosx --minimum-deployment-target 26.0` exit 0
- [x] `Color("surface")` và 9 màu còn lại resolve đúng, không ra fallback
- [x] Mọi cặp text/nền đạt ≥ 4.5:1; UI component ≥ 3:1; đo ở **cả** light và dark
- [x] `docs/design-guidelines.md` viết bằng tiếng Anh, ghi hex + contrast ratio **đo được**, không ước lượng
- [x] 4 file tiếng Việt sẵn có trong `docs/` không bị sửa
- [x] App vẫn compile và chạy được (chưa view nào dùng token cũng phải không vỡ)

## Risk Assessment

**Rủi ro: palette riêng không đạt contrast ở dark mode.** Rất hay gặp — màu đẹp trên nền sáng thường tối quá trên nền tối.
*Tín hiệu:* đo ở bước 6 thấy < 4.5:1.
*Phản ứng đã định:* chỉnh lightness của biến thể Dark cho tới khi đạt; nếu accent không thể vừa đạt contrast vừa giữ nhận diện thì tách làm hai giá trị (accent-onLight, accent-onDark) thay vì hạ chuẩn.

**Rủi ro: xcodegen không nhận `.xcassets` đặt trong `Sources/`.**
*Tín hiệu:* `Color("surface")` ra màu hồng fallback sau bước 4.
*Phản ứng đã định:* thêm mục `resources:` vào `project.yml` cho target AgeOS. Đây là sửa config, không phải đổi kiến trúc.

**Rủi ro: Increase Contrast làm màu ngữ nghĩa mất phân biệt.**
*Tín hiệu:* bật Increase Contrast trong System Settings, các status color nhìn giống nhau.
*Phản ứng đã định:* bổ sung biến thể High Contrast trong Asset Catalog cho các status color.
