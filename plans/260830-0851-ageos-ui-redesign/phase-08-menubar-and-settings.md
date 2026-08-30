---
title: "Phase 8: MenuBar And Settings"
status: done
phase: 8
priority: P3
effort: "0.5d"
dependencies: [2, 4]
---

# Phase 8: MenuBar And Settings

## Overview

Đưa `MenuBarView` và `SettingsView` lên design system và tiếng Anh, để không còn bề mặt nào của app bị bỏ lại. Cả hai đang nằm trong `AgeOSApp.swift`.

## Requirements

- Functional: menu bar giữ nguyên 4 hành động hiện có (xem trạng thái, sync, doctor, thoát).
- Functional: Settings hiển thị đủ thông tin hiện có + link mở thư mục library.
- Non-functional: tiếng Anh, dùng token và component chung.

## Architecture

**Hiện trạng `MenuBarView`** — list `Text` + `Button` trần, không cấu trúc:
```swift
Text("AgeOS — \(managed) skill được quản lý")
if let sync = model.lastSyncAt { Text("Sync gần nhất: …") }
Divider()
Button("Sync tất cả nguồn") { … }
Button("Chạy doctor") { … }
Divider()
Button("Thoát AgeOS") { … }
```

Ràng buộc quan trọng: nội dung `MenuBarExtra` là **menu của hệ thống**, không phải view thường. Component tuỳ biến như `StatTile` hay `SectionCard` **không** render được trong đó — macOS chỉ nhận menu item. Nên phase này với menu bar là **đổi chuỗi + bổ sung thông tin**, không phải áp component.

Đây là lý do tách riêng thành phase: nó trông giống Phase 7 nhưng ràng buộc kỹ thuật khác hẳn.

Bổ sung cho menu bar (vẫn trong giới hạn menu item):
- Dòng trạng thái gọn: số skill managed + số vấn đề đang có (từ `attentionSummary` của Phase 5).
- Mục "Open AgeOS" mở cửa sổ chính — hiện chưa có, người dùng đóng cửa sổ rồi thì chỉ còn cách thoát app.

**`SettingsView`** là view thường, áp được component. Hiện là `Form` + `LabeledContent` thô. Bổ sung:
- Dùng `SectionCard` gom theo nhóm: Library / Adapters / Sources.
- Nút "Reveal in Finder" cho `AgeOSHome().root` — path đang hiện dạng text không bấm được.
- Giữ nguyên ghi chú ±20% (nội dung đúng, chỉ dịch).

## Related Code Files

- Modify: `apps/AgeOS/Sources/AgeOSApp.swift` (`MenuBarView`, `SettingsView`)

Cân nhắc tách `MenuBarView` và `SettingsView` ra file riêng nếu `AgeOSApp.swift` vượt ~200 dòng sau khi sửa — hiện đang ~160 dòng và chứa 5 kiểu (`AgeOSApp`, `ContentView`, `ErrorBanner`, `DoctorSuggestion`, `MenuBarView`, `SettingsView`). Tách theo ranh giới thật, không tách cho đủ số file.

## Implementation Steps

1. Dịch chuỗi của `MenuBarView` và `SettingsView` sang tiếng Anh (bổ sung vào String Catalog Phase 4).
2. Thêm dòng trạng thái vấn đề vào menu bar, đọc từ `attentionSummary`.
3. Thêm mục "Open AgeOS" dùng `@Environment(\.openWindow)` — đã import sẵn trong `MenuBarView` nhưng chưa dùng.
4. `SettingsView`: gom nhóm bằng `SectionCard`, thêm nút "Reveal in Finder" cho library root.
5. Đánh giá kích thước `AgeOSApp.swift`; tách file nếu vượt ngưỡng.
6. Chạy thử: đóng cửa sổ chính, dùng menu bar mở lại; kiểm tra mọi hành động menu bar còn chạy.

## Success Criteria

- [x] Menu bar và Settings hoàn toàn tiếng Anh
- [x] Menu bar hiện số vấn đề đang có, khớp Overview — cùng đọc `attentionSummary` với Overview
- [~] Mục "Open AgeOS" mở lại cửa sổ chính sau khi đã đóng — **chưa chạy được**. Lưu ý: cách plan đề xuất (đặt id cho WindowGroup) đã bị thực nghiệm bác bỏ, xem Session 3; đã đổi sang đường reopen của AppKit
- [~] Settings có nút "Reveal in Finder" hoạt động — chưa chạy tay được
- [~] Mọi hành động menu bar cũ còn chạy (sync, doctor, quit) — chưa chạy tay được
- [x] `swift test` xanh

## Risk Assessment

**Rủi ro: cố áp component tuỳ biến vào `MenuBarExtra` rồi không render.** Menu hệ thống chỉ nhận một tập control hạn chế.
*Tín hiệu:* menu hiện trống hoặc item mất khi thêm view tuỳ biến.
*Phản ứng đã định:* giữ menu bar ở dạng menu item chuẩn. Nếu thật sự cần bố cục giàu hơn thì đổi `MenuBarExtra` sang `.menuBarExtraStyle(.window)` — nhưng đó là đổi hành vi, cần user đồng ý trước, không tự quyết.

**Rủi ro: `openWindow` không mở lại được cửa sổ chính** vì `WindowGroup` chưa có id.
*Tín hiệu:* bấm "Open AgeOS" không có gì xảy ra.
*Phản ứng đã định:* đặt id cho `WindowGroup` (`WindowGroup(id: "main")`) và gọi `openWindow(id: "main")`. Đây là sửa nhỏ, không ảnh hưởng phase khác.
