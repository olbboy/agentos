---
title: "Phase 5: Overview And IA"
status: done
phase: 5
priority: P1
effort: "1.5d"
dependencies: [2, 4]
---

# Phase 5: Overview And IA

## Overview

Thêm màn `Overview` làm màn đích khi mở app, gom 6 mục sidebar phẳng thành 3 nhóm, và hoà tan `AdoptView`. Đây là phase giải P1 (không có first-run story) và P3 (không so sánh được cross-agent).

## Requirements

- Functional: mở app với `~/.ageos/` rỗng → thấy Overview có inventory quét từ máy thật + CTA import.
- Functional: Overview so sánh được budget mọi agent trên **chung một thang**.
- Functional: mọi tile trên Overview deep-link sang màn chi tiết và mang CTA riêng — không phải summary chỉ-đọc.
- Functional: chức năng của Adopt không mất, chỉ chuyển chỗ.
- Non-functional: không thêm dữ liệu mới từ core — mọi thứ Overview cần đã có trong `AppModel`.

## Architecture

**Vì sao hoà tan Adopt thay vì giữ làm tab:** Adopt là câu trả lời cho "máy tôi đang ra sao" — đúng là câu hỏi đầu tiên người dùng có khi mở app. Để nó ở tab 5 nghĩa là câu trả lời mạnh nhất bị chôn. Chuyển nội dung Adopt lên Overview vừa giải P1 vừa cho Overview lý do tồn tại.

**Ánh xạ Adopt → chỗ mới:**

| Thành phần Adopt | Chỗ mới |
|---|---|
| 4 số thống kê (`totalDistinctSkills`, `agents.count`, `totalLoadEntries`, số skill ≥2 agent) | Dải `StatTile` trên Overview |
| Danh sách duplicate path per-agent | Nhóm Warning trong Diagnostics (Phase 6) |
| Nút "Import vào library" + confirm | CTA chính lúc cold-start; action thường trực sau đó |
| `AdoptView.stat()` | `StatTile` (Phase 2) |

**IA mới trong `ContentView`:**
```
Overview
Distribute
  ├ Library
  ├ Target Matrix
  └ MCP Servers
Health
  ├ Context Budget
  └ Diagnostics
```
Dùng `Section` trong `List` của sidebar để tạo nhóm. `enum Section` hiện tại tách thành `enum Destination` (7 đích) + nhóm hiển thị.

**Bố cục Overview:**

1. **Dải metric** — 4 `StatTile` ngang: skills distinct · agents detected · managed by AgeOS · loaded in ≥2 agents. Nguồn: `model.inventory`, `model.lock`.
2. **Split Healthy / Needs attention** — hai `SectionCard` cạnh nhau. "Needs attention" cộng dồn từ `scanReport` (exact dupes + near dupes + deprecated + lint) và `doctorFindings`, mỗi loại một dòng deep-link sang Diagnostics.
3. **Hàng budget cross-agent** — mỗi agent một `RatioMeter`, `scaleMax` tính **một lần** cho cả nhóm:
   ```swift
   // scaleMax chung = max của (mọi totalTokens, mọi threshold).
   // Lấy cả threshold vào max để agent đang dưới ngưỡng vẫn thấy được
   // mình còn cách ngưỡng bao xa, thay vì thanh luôn đầy khung.
   let scaleMax = max(
       model.budgets.map(\.totalTokens).max() ?? 0,
       model.budgets.compactMap(\.warnThreshold).max() ?? 0
   )
   ```
4. **Cold-start hero** — khi `model.lock.skills.isEmpty`: card lớn "Found N skills across M agents on this Mac" + primary "Import into library" + secondary "Add a source". Số liệu lấy từ `model.inventory` (đã quét lúc `start()`), nên hiện được ngay cả khi library rỗng.
5. **Footer** — last sync + nút Sync.

**Điểm mấu chốt về cold-start:** `AppModel.start()` đã gọi `refreshAll()` trong đó có `EffectiveLoadScanner.scan()`. Nghĩa là inventory có sẵn **trước cả khi** người dùng thêm nguồn nào. Đây là lý do màn cold-start có nội dung thật chứ không phải khung rỗng.

## Related Code Files

- Create: `apps/AgeOS/Sources/Views/OverviewView.swift`
- Modify: `apps/AgeOS/Sources/AgeOSApp.swift` (`ContentView`: `enum Section` → `Destination` + nhóm, selection mặc định = `.overview`)
- Delete: `apps/AgeOS/Sources/Views/AdoptView.swift`
- Modify: `apps/AgeOS/Sources/AppModel.swift` (giữ `runAdopt`, có thể thêm computed property gom "needs attention")
- Modify: `apps/AgeOS/Tests/AppModelTests.swift` (nếu có test chạm AdoptView)

## Implementation Steps

1. Viết `OverviewView.swift` với 5 khối trên, dùng component Phase 2.
2. Thêm computed property vào `AppModel` gom số "needs attention" theo loại — để Overview và Diagnostics dùng chung một nguồn, không đếm hai kiểu:
   ```swift
   /// Gom mọi vấn đề đang có, phân theo severity. Overview hiện số đếm,
   /// Diagnostics hiện chi tiết — cùng một nguồn để hai màn không lệch nhau.
   var attentionSummary: (errors: Int, warnings: Int, info: Int) { … }
   ```
3. Sửa `ContentView`: đổi `enum Section` thành `Destination` với 7 case, dựng sidebar có `Section` header cho Distribute / Health, đặt `@State private var selection: Destination = .overview`.
4. Chuyển logic import từ `AdoptView` sang Overview (giữ nguyên `confirmationDialog`, chỉ đổi chỗ đặt).
5. Xoá `AdoptView.swift`.
6. Test cold-start thật: `AGEOS_HOME=$(mktemp -d) open apps/AgeOS/…app` hoặc chạy qua Xcode với env đó — xác nhận Overview có nội dung, không rỗng.
7. Test warm-start: chạy trên `~/.ageos` thật, xác nhận số liệu khớp `ageos adopt` từ CLI.

## Success Criteria

- [~] Mở app với `AGEOS_HOME` rỗng → Overview hiện "Found N skills across M agents", N và M > 0 trên máy có agent — **chưa chạy được**: XCUITest thiếu quyền Accessibility (Session 3). Test `testColdStartLandsOnOverview` đã viết sẵn
- [x] Sidebar có 3 nhóm, `Overview` là selection mặc định
- [~] 4 `StatTile` khớp số của `ageos adopt --json` — chưa đối chiếu được bằng mắt (không có GUI access)
- [x] Mọi `RatioMeter` trên Overview dùng **cùng** `scaleMax` (kiểm tra bằng cách đọc code, không phải bằng mắt) — verified bằng đọc code: `OverviewView.budgetScaleMax` tính một lần, truyền vào mọi meter
- [x] Mỗi tile "needs attention" bấm được, chuyển sang Diagnostics — verified bằng đọc code: `attentionRow` là Button đặt `selection = .diagnostics`
- [~] Nút import hoạt động, kết quả khớp `AdoptView` cũ — chưa chạy được bằng tay; logic chuyển nguyên từ `AdoptView.runAdopt`
- [x] `AdoptView.swift` đã xoá, không còn tham chiếu
- [x] `swift test` xanh — 69 core + 22 app

## Risk Assessment

**Rủi ro: Overview thành dashboard chết** — đẹp nhưng không ai vào vì việc thật ở Target Matrix.
*Tín hiệu:* review thấy có tile chỉ hiện số, không bấm được, không có CTA.
*Phản ứng đã định:* đây là điều kiện nghiệm thu, không phải mong muốn. Tile nào không deep-link được thì bỏ khỏi Overview — thà ít tile mà mỗi tile dẫn đi đâu đó.

**Rủi ro: người dùng cũ mất tab Adopt** và không biết tìm chức năng import ở đâu.
*Tín hiệu:* phản hồi sau release.
*Phản ứng đã định:* giữ action "Import unmanaged skills" thường trực trên Overview (không chỉ lúc cold-start), và ghi vào release note rằng Adopt đã chuyển lên Overview.

**Rủi ro: `scan()` chậm làm cold-start treo.** `EffectiveLoadScanner.scan()` duyệt filesystem của mọi agent.
*Tín hiệu:* mở app thấy khựng trước khi Overview hiện.
*Phản ứng đã định:* `AppModel.run` đã chạy việc nặng detached rồi cập nhật trên MainActor — nếu vẫn chậm thì hiện `StatTile` ở trạng thái loading (skeleton) thay vì chặn cả màn.

**Rủi ro: Overview và Diagnostics đếm lệch nhau** vì mỗi màn tự tổng hợp.
*Tín hiệu:* Overview báo 5 warning, Diagnostics liệt kê 7.
*Phản ứng đã định:* bước 2 bắt buộc — một computed property duy nhất trên `AppModel`, hai màn cùng đọc. Không màn nào tự đếm lại.
