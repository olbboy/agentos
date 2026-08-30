---
title: "Phase 4: App String Catalog"
status: done
phase: 4
priority: P1
effort: "0.5d"
dependencies: [3]
---

# Phase 4: App String Catalog

## Overview

Dựng `Localizable.xcstrings` (String Catalog) cho app với base `en`, và chuyển mọi chuỗi UI hiện có từ tiếng Việt sang tiếng Anh. Phụ thuộc Phase 3 để app và engine nói cùng một ngôn ngữ.

## Requirements

- Functional: mọi chuỗi UI của app là tiếng Anh, quản lý qua String Catalog.
- Functional: **bật `SWIFT_EMIT_LOC_STRINGS` và `LOCALIZATION_PREFERS_STRING_CATALOGS` trong `project.yml` TRƯỚC khi tạo catalog** — nếu không, catalog sinh ra rỗng và lỗi chỉ lộ ra ở Phase 9.
- Non-functional: sau khi bật hai setting đó, không cần quản key thủ công — Xcode tự trích từ literal trong `Text(...)`, `Label(...)`, `.accessibilityLabel(...)`.
- Non-functional: hạ tầng sẵn sàng để thêm tiếng Việt sau như một translation, không phải sửa lại code.

## Architecture

**String Catalog (`.xcstrings`) là gì và vì sao chọn nó:** đây là format localization của Xcode 15+, thay cho `.strings` cũ. Điểm khác biệt quan trọng: Xcode **tự quét** code lúc biên dịch, tìm mọi string literal nằm trong ngữ cảnh `LocalizedStringKey` (chính là tham số của `Text`, `Label`, `Button`…), và tự thêm vào catalog. Không phải tự đặt key, không phải nhớ đồng bộ.

> **CẢNH BÁO — đã đo trên chính project này, không phải suy đoán.**
> Cơ chế tự trích **KHÔNG mặc định bật ở đây**. Sinh project rồi truy vấn setting hiệu lực cho ra:
> ```
> SWIFT_EMIT_LOC_STRINGS = NO
> LOCALIZATION_PREFERS_STRING_CATALOGS = NO
> ```
> Tài liệu phổ biến nói "enabled by default" — đúng, nhưng đó là mặc định của **template project Xcode**, không phải mặc định của hệ thống. `apps/AgeOS/project.yml` do xcodegen sinh, không đi qua template, nên không thừa hưởng.
> **Hệ quả nếu bỏ qua:** tạo `Localizable.xcstrings`, biên dịch, catalog **rỗng**. Không lỗi, không cảnh báo. Sai sót chỉ lộ ra ở Phase 9 khi rà từng màn.
> Phần xcodegen làm đúng sẵn: `developmentRegion = en` và `knownRegions = (Base, en)` — không cần đụng.

Hệ quả với cách viết code: `Text("Library")` được trích tự động; `Text(someVariable)` thì không, vì Xcode không biết giá trị lúc build. Chuỗi động phải xử lý riêng — nhưng ở AgeOS phần lớn chuỗi động đến từ core (đã tiếng Anh sau Phase 3) nên hiển thị nguyên văn là đúng.

**Bẫy thường gặp:** `Text(verbatim: "…")` cố tình **không** localize. Dùng nó cho dữ liệu (skill id, path, số) để tránh Xcode nhét dữ liệu vào catalog.

Bảng chuyển đổi các chuỗi hiện có (không đầy đủ, để tham chiếu khi làm):

| Hiện tại | Sau |
|---|---|
| `"Thêm & Sync"` | `"Add & Sync"` |
| `"Tìm skill"` | `"Search skills"` |
| `"Chỉ deprecated"` | `"Deprecated only"` |
| `"Quét"` | `"Scan"` |
| `"Chạy doctor"` | `"Run doctor"` |
| `"Đóng"` | `"Dismiss"` |
| `"Hủy"` | `"Cancel"` |
| `"Library trống"` | `"Library is empty"` |
| `"Chưa quét"` | `"Not scanned yet"` |
| `"Không có"` | `"None"` |
| `"chưa đo"` | `"Not measured"` |
| `"Thoát AgeOS"` | `"Quit AgeOS"` |

## Related Code Files

- **Modify (BẮT BUỘC, làm trước mọi thứ): `apps/AgeOS/project.yml`** — thêm vào `targets.AgeOS.settings.base`:
  ```yaml
  SWIFT_EMIT_LOC_STRINGS: YES
  LOCALIZATION_PREFERS_STRING_CATALOGS: YES
  ```
- Create: `apps/AgeOS/Sources/Localizable.xcstrings`
- Modify: `apps/AgeOS/Sources/AgeOSApp.swift`
- Modify: `apps/AgeOS/Sources/Views/LibraryView.swift`
- Modify: `apps/AgeOS/Sources/Views/ScanView.swift`
- Modify: `apps/AgeOS/Sources/Views/AdoptView.swift`
- Modify: `apps/AgeOS/Sources/Views/McpView.swift`
- Modify: `apps/AgeOS/Sources/Views/TargetMatrixView.swift`
- Modify: `apps/AgeOS/Sources/Views/BudgetView.swift`
## Implementation Steps

0. **Bật hai setting trong `project.yml`, chạy `xcodegen generate`, rồi xác nhận bằng lệnh — không tin mặc định:**
   ```bash
   cd apps/AgeOS && xcodegen generate
   xcodebuild -project AgeOS.xcodeproj -target AgeOS -showBuildSettings \
     | grep -E "SWIFT_EMIT_LOC_STRINGS|LOCALIZATION_PREFERS_STRING_CATALOGS"
   ```
   Cả hai phải in ra `= YES` trước khi sang bước 1. Nếu còn `NO`, dừng lại — mọi việc phía sau sẽ vô ích.
1. Tạo `Localizable.xcstrings` trong `apps/AgeOS/Sources/`, đặt base language là `en`.
2. Dịch chuỗi trong 7 file view theo bảng trên. Sửa trực tiếp literal trong code — **không** tạo key thủ công.
3. Bọc dữ liệu bằng `Text(verbatim:)` ở chỗ đang hiện skill id, path, version, con số — để chúng không bị trích vào catalog.
4. Build app; mở `Localizable.xcstrings` trong Xcode, xác nhận mọi chuỗi UI đã tự xuất hiện với trạng thái đã dịch.
5. Kiểm tra sót: `grep -rn '[àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ]' apps/AgeOS/Sources/` — chỉ còn khớp trong comment.
6. Chạy app, rà từng màn xác nhận không sót chuỗi tiếng Việt (kể cả confirmation dialog và accessibility label).

## Success Criteria

- [x] `xcodebuild -showBuildSettings` in ra `SWIFT_EMIT_LOC_STRINGS = YES` **và** `LOCALIZATION_PREFERS_STRING_CATALOGS = YES`
- [x] Sau khi biên dịch, `Localizable.xcstrings` **không rỗng** — đếm được số key > 0 (`jq '.strings | length' Localizable.xcstrings`)
- [x] `Localizable.xcstrings` tồn tại, base `en`, được nhận là resource
- [x] Grep tiếng Việt trong `apps/AgeOS/Sources/` chỉ còn khớp trong comment
- [x] Mọi chuỗi UI xuất hiện trong catalog sau khi build (không sót chuỗi nào ngoài catalog)
- [x] Dữ liệu (skill id, path, version) dùng `Text(verbatim:)`, không lọt vào catalog
- [x] Confirmation dialog và `.accessibilityLabel` cũng đã sang tiếng Anh
- [x] App chạy, mọi màn tiếng Anh, không sót

## Risk Assessment

**Rủi ro cao nhất: catalog rỗng mà không có lỗi.** Đây là rủi ro đã **đo được**, không phải giả định: `SWIFT_EMIT_LOC_STRINGS = NO` và `LOCALIZATION_PREFERS_STRING_CATALOGS = NO` trên project hiện tại.
*Tín hiệu:* biên dịch xong, mở `Localizable.xcstrings` thấy không key nào.
*Phản ứng đã định:* bước 0 là cổng chặn — không sang bước 1 khi hai setting chưa `= YES`. Điều kiện nghiệm thu đếm số key > 0 để chặn lần hai.

**Rủi ro: dữ liệu động bị nhét vào String Catalog**, làm catalog phình và vô nghĩa (mỗi skill id thành một "chuỗi cần dịch").
*Tín hiệu:* mở catalog thấy các entry là skill id hoặc path.
*Phản ứng đã định:* bọc chỗ đó bằng `Text(verbatim:)`, xoá entry rác khỏi catalog.

**Rủi ro: chuỗi nội suy mất nghĩa khi dịch** — ví dụ `"Library (\(count))"` cần thứ tự khác ở ngôn ngữ khác.
*Tín hiệu:* chuỗi có nội suy nằm giữa câu.
*Phản ứng đã định:* để nguyên ở phase này (base `en` không có vấn đề thứ tự); ghi chú lại trong catalog comment để người dịch tiếng Việt sau này biết.

**Rủi ro: `.accessibilityLabel` bị bỏ sót** vì không hiện trên màn hình.
*Tín hiệu:* bước 5 grep vẫn còn khớp trong `.accessibilityLabel(...)`.
*Phản ứng đã định:* grep riêng `grep -rn 'accessibilityLabel' apps/AgeOS/Sources/` và rà từng dòng — đây là bề mặt dễ quên nhất.
