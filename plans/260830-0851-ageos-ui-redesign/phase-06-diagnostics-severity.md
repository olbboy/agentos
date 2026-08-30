---
title: "Phase 6: Diagnostics Severity"
status: done
phase: 6
priority: P1
effort: "1d"
dependencies: [2, 4]
---

# Phase 6: Diagnostics Severity

## Overview

Gộp `ScanView` và output của Doctor thành một màn `DiagnosticsView` phân theo severity, mỗi finding kèm hành động sửa tại chỗ, và tách `doctor --fix` khỏi toolbar. Giải P4 và P5.

## Requirements

- Functional: mọi finding gom theo Error / Warning / Info, mỗi nhóm hiện số đếm.
- Functional: mỗi `FindingRow` mang một `StatusPill` nói rõ có sửa tự động được hay không; không row nào để trống trạng thái.
- Functional: `doctor --fix` là CTA destructive **duy nhất** ở cuối màn kèm confirm liệt kê đúng N việc; **không** truy cập được từ toolbar, và **không** có bản sao per-row.
- Non-functional: số đếm khớp Overview (dùng chung `attentionSummary` của Phase 5).

## Architecture

**Vì sao gộp Scan và Doctor:** với người dùng, cả hai đều trả lời "có gì sai không". Tách làm hai mô hình bắt họ tự nhớ cái nào tìm được cái gì. Gộp lại rồi phân theo mức nghiêm trọng thì thứ tự ưu tiên tự hiện ra.

**Bảng severity — mọi loại finding phải nằm ở đúng một hàng:**

| Severity | Nguồn | Vì sao mức này |
|---|---|---|
| **Error** | `Doctor.Kind.brokenLink`, `.missingTarget`, `.storeMissing`, `.adapterUnknown` | Phân phối đang hỏng thật — agent không load được skill |
| **Error** | `scanReport.exactDupes` | Cùng một skill tồn tại hai bản y hệt, chắc chắn lãng phí |
| **Warning** | `Doctor.Kind.copyDrift`, `.orphanFile`, `.agentPathMissing`, `.userShadow` | Lệch trạng thái, chưa hỏng nhưng sẽ gây bất ngờ |
| **Warning** | `scanReport.nearDupes`, `scanReport.deprecated` | Cần người quyết, không tự sửa được |
| **Warning** | duplicate load path (từ `inventory.agents[].duplicated`) | Chuyển từ AdoptView sang, Phase 5 |
| **Info** | `scanReport.lintFindings` | Gợi ý chất lượng mô tả, không ảnh hưởng vận hành |

**Ràng buộc API đã verify (validate session 1):** `Doctor.run(fix: Bool)` ở `Sources/AgeOSCore/doctor/Doctor.swift:38` là **all-or-nothing**, không nhận filter. Nên **không có nút "Repair" riêng cho từng dòng** — hứa sửa một finding rồi chạy fix toàn cục là nói dối người dùng. Quyết định: bỏ per-row repair, chỉ giữ một CTA toàn cục.

**Action cho từng loại — phải rõ cái nào tự sửa được:**

| Loại | Hiển thị trên row | Action trên row |
|---|---|---|
| `Doctor.Finding` có `fixable == true` | `StatusPill` "Fixable" | "Reveal in Finder" cho `finding.path` — việc sửa do CTA cuối màn lo |
| `Doctor.Finding` có `fixable == false` | `StatusPill` "No automatic fix" | "Reveal in Finder" |
| exact / near dupe | `StatusPill` "No automatic fix" | "Compare" mở hai path trong Finder; không tự xoá |
| deprecated | `StatusPill` "Action required" | "Disable everywhere" → `model.toggle(..., enabled: false)` cho mọi adapter đang bật |
| lint finding | `StatusPill` "No automatic fix" | không có (gợi ý viết mô tả, máy không sửa hộ được) |

Chỉ **một** loại action thực sự thay đổi trạng thái ở cấp row: "Disable everywhere" cho deprecated — nó gọi `model.toggle`, một API đã có và có tính lọc thật. Mọi thứ còn lại hoặc là điều hướng (Reveal, Compare) hoặc dồn vào CTA cuối màn.

**Vì sao không tự xoá dupe:** xoá skill là hành động mất dữ liệu và không thể lùi từ trong app. AgeOS đã có nguyên tắc "chỉ gỡ thứ mình tạo ra" — giữ nguyên tắc đó ở UI.

**Bố cục:**
```
[Summary bar]  Healthy · Needs attention (E/W/I counts)
[Errors (N)]   ← nhóm có viền màu + số đếm
  FindingRow …
[Warnings (N)]
  FindingRow …
[Info (N)]
  FindingRow …
[Footer]  "How these findings are generated" + [Rerun scan]
[Destructive CTA]  "Repair all fixable (N)" → confirmationDialog
```

Nhóm rỗng thì thu gọn thành một dòng "No errors", không ẩn hẳn — người dùng cần biết là đã kiểm và sạch, khác với chưa kiểm.

## Related Code Files

- Create: `apps/AgeOS/Sources/Views/DiagnosticsView.swift`
- Create: `apps/AgeOS/Sources/Views/DiagnosticSeverity.swift` (enum + hàm map từ finding sang severity)
- Delete: `apps/AgeOS/Sources/Views/ScanView.swift`
- Modify: `apps/AgeOS/Sources/AgeOSApp.swift` (`Destination.scan` → `.diagnostics`)
- Modify: `apps/AgeOS/Sources/AppModel.swift` (nếu cần action per-finding)
- Create: `apps/AgeOS/Tests/DiagnosticSeverityTests.swift` — dùng **swift-testing** (`import Testing`, `@Test`, `#expect`), khớp quy ước áp đảo của repo và khớp Phase 2. Lý do đầy đủ ghi ở Phase 2.

## Implementation Steps

1. Viết `DiagnosticSeverity.swift`: enum `Severity { error, warning, info }` + hàm thuần map từng loại finding sang severity theo bảng trên. Tách ra file riêng vì đây là **logic thuần, test được** — không nên chôn trong view.
2. Viết test cho hàm map: mỗi `Doctor.Kind` (8 case) phải ra đúng severity; thêm test bắt case mới — nếu core thêm `Kind` mà quên map thì test phải đỏ (dùng `switch` không có `default` để compiler bắt luôn).
3. Viết `DiagnosticsView.swift` theo bố cục trên, dùng `SectionCard` + `FindingRow` + `StatusPill`.
4. Nối action cho từng loại theo bảng. Mỗi row phải có `StatusPill` trạng thái — **không** để trống. Không thêm nút "Repair" per-row: `Doctor.run(fix:)` không lọc được.
5. Chuyển CTA `doctor --fix` xuống cuối màn, style destructive, giữ nguyên `confirmationDialog` và nội dung cảnh báo hiện có (nó đã nói rõ sẽ ĐÈ chỉnh sửa tay trên bản copy drift — giữ cảnh báo đó).
6. Xoá `ScanView.swift`, cập nhật `Destination`.
7. Đối chiếu số đếm với Overview — phải khớp, vì cùng đọc `attentionSummary`.

## Success Criteria

- [x] 3 nhóm severity, mỗi nhóm có số đếm; nhóm rỗng hiện "No errors" chứ không ẩn
- [x] Cả 8 `Doctor.Kind` đều được map, có test phủ từng case
- [x] `switch` map severity không có `default` (compiler bắt case mới)
- [x] Mỗi `FindingRow` có `StatusPill` trạng thái — không row nào trống
- [x] Không có nút "Repair" per-row; `grep -c "runDoctor(fix: true)" DiagnosticsView.swift` trả về đúng `1` (chỉ CTA cuối màn)
- [x] `doctor --fix` không xuất hiện trong `.toolbar`
- [x] Confirm dialog liệt kê đúng số N việc sẽ làm, không nói chung chung
- [x] CTA destructive giữ nguyên nội dung cảnh báo về việc đè bản copy drift
- [x] Số đếm khớp Overview
- [x] Không có action nào xoá skill tự động
- [x] `swift test` xanh

## Risk Assessment

**Rủi ro: core thêm `Doctor.Kind` mới, quên map, finding rơi vào hư không.**
*Tín hiệu:* build lỗi (nếu `switch` viết đúng) hoặc finding không hiện (nếu lỡ có `default`).
*Phản ứng đã định:* cấm `default` trong hàm map — đây là lý do bước 2 nêu rõ. Compiler là hàng rào rẻ nhất.

**Rủi ro: "Repair all fixable" chạy `doctor --fix` toàn cục, sửa cả thứ người dùng không muốn.** Đây là **giới hạn đã biết và đã chấp nhận** ở validate session 1, không phải sơ suất: `Doctor.run(fix:)` không lọc được, và thêm filter vào core đã bị loại để giữ ranh giới "không đổi hành vi core".
*Tín hiệu:* người dùng chỉ muốn sửa 1 broken link nhưng bị đè cả copy drift đã chỉnh tay.
*Phản ứng đã định:* confirm dialog liệt kê **cụ thể** N việc sẽ làm, tách rõ dòng nào là `copyDrift` (loại duy nhất đè lên chỉnh sửa tay). Nếu người dùng về sau vẫn thấy thô thì mở lại quyết định "thêm `run(fix:only:)` vào core" như một plan riêng — không nhét vào phase này.

**Rủi ro: gộp Scan + Doctor làm mất phân biệt "chưa chạy" và "chạy rồi, sạch".**
*Tín hiệu:* màn trống, không rõ đã quét chưa.
*Phản ứng đã định:* ba trạng thái tách bạch: chưa quét (empty state + CTA Scan), đã quét & sạch ("No errors" mỗi nhóm + thời điểm quét), đã quét & có vấn đề (danh sách).
