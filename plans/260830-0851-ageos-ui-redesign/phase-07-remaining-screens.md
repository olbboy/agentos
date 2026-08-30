---
title: "Phase 7: Remaining Screens"
status: done
phase: 7
priority: P2
effort: "1.5d"
dependencies: [2, 4]
---

# Phase 7: Remaining Screens

## Overview

Viết lại 4 màn còn lại trên design system: `LibraryView`, `TargetMatrixView`, `BudgetView`, `McpView`. Không đổi chức năng — đổi cách trình bày và bổ sung tín hiệu còn thiếu.

## Requirements

- Functional: giữ nguyên mọi hành vi hiện có (thêm nguồn, sync, toggle, health check).
- Functional: Target Matrix đọc được trạng thái bật/tắt bằng mắt, không cần soi từng switch.
- Functional: Library hiện được nguồn gốc và token ước tính của mỗi skill.
- Non-functional: không literal spacing/font/color còn lại trong 4 file.

## Architecture

### LibraryView

Vấn đề hiện tại: mỗi dòng chỉ có id, version, description. Không biết skill đến từ nguồn nào, tốn bao nhiêu token, đang bật ở mấy agent — tức là không đủ thông tin để quyết định có bật hay không.

Bổ sung mỗi dòng:
- **Nguồn** — `skill.sourceId`, hiện dạng `StatusPill` tone neutral.
- **Token ước tính** — `BudgetMeter.skillTokens(name:description:truncateChars:)` (đã public ở Phase 2), truncate 0 cho con số chung.
- **Số agent đang bật** — đếm **số adapterId phân biệt**, không phải `targets.count`. Key của `targets` là `<adapterId>@global` **hoặc** `<adapterId>@<projectPath>` (xem `Lockfile.SkillEntry.targets`), nên một adapter có thể chiếm nhiều entry và `targets.count` sẽ đếm thừa. Dùng đúng cách `AppModel.isEnabled` đang làm — so khớp `hasPrefix("\(adapterId)@")`:
  ```swift
  // Đếm adapter phân biệt, không đếm entry: một adapter có thể có
  // cả target global lẫn target theo project.
  let enabledAdapters = Set(
      (lock.skills[skill.id]?.targets.keys ?? [:].keys)
          .compactMap { $0.split(separator: "@").first.map(String.init) }
  ).count
  ```

Filter đơn `showDeprecatedOnly` thay bằng dropdown ba chiều: source / deprecated / enabled-anywhere. Gộp vào một `Menu` thay vì ba control rời — ít mực hơn, và với chỉ 3 facet thì dropdown đúng hơn sidebar cố định.

**Quality score có chủ ý KHÔNG đưa vào danh sách.** `QualityScorer.score(_:)` cần `ParsedSkill` (phải đọc và parse `SKILL.md`), không phải `IndexDB.SkillRow`. Chấm điểm mọi dòng khi cuộn sẽ phải parse cả library. Nếu muốn hiện thì làm dạng detail-on-demand — chấm khi người dùng chọn một skill. Ghi nhận là việc ngoài phạm vi phase này.

### TargetMatrixView

Vấn đề: lưới switch mini không màu, liếc không ra agent nào đang bật gì.

- **Tint nền dòng** theo số target đang bật (0 → nền thường, ≥1 → nền accent rất nhạt). Đây là pattern Qatalog — trạng thái đọc được không cần nhìn switch.
- **Header cột** hiện thêm mode (`symlink` / `copy`) và badge `verified`. Thông tin này đang nằm trong `.help()` tooltip, tức là ẩn. Adapter chưa verified là thứ người dùng cần biết trước khi bật, không phải sau khi hover.
- Giữ `Table` + `TableColumnForEach` — cấu trúc đang đúng, chỉ thiếu tín hiệu thị giác.

### BudgetView

Giữ chi tiết per-agent (Overview đã lo phần so sánh). Thay đổi:
- `GroupBox` → `SectionCard`, `ProgressView` → `RatioMeter`.
- Top skills đổi sang dạng receipt itemized: thêm **% của tổng** mỗi dòng, không chỉ con số tuyệt đối.
- Disclaimer ±20% chuyển từ **đầu** xuống **cuối** màn, kèm giải thích cách tính (hệ số 4 bytes/token). Ở đầu màn nó chặn nội dung; ở cuối nó trả lời câu hỏi "số này đáng tin không" đúng lúc người dùng bắt đầu hỏi.

### McpView

- Tách nhóm **Enabled** / **Available** thay vì một list phẳng (pattern Rox).
- `HealthBadge` → `StatusPill`.
- Cảnh báo env nhạy cảm giữ nguyên nội dung, đổi sang `StatusPill` tone warning.

## Related Code Files

- Modify: `apps/AgeOS/Sources/Views/LibraryView.swift`
- Modify: `apps/AgeOS/Sources/Views/TargetMatrixView.swift`
- Modify: `apps/AgeOS/Sources/Views/BudgetView.swift`
- Modify: `apps/AgeOS/Sources/Views/McpView.swift`

## Implementation Steps

1. `LibraryView`: thay `GroupBox`/`List` row bằng component; thêm 3 tín hiệu (nguồn, token, số agent); đổi toggle filter thành `Menu` ba chiều.
2. `TargetMatrixView`: thêm tint nền theo trạng thái; đưa mode + verified từ tooltip lên header cột.
3. `BudgetView`: đổi sang `SectionCard` + `RatioMeter`; thêm % vào top skills; chuyển disclaimer xuống cuối.
4. `McpView`: tách Enabled / Available; đổi badge sang `StatusPill`.
5. Grep xác nhận sạch literal:
   ```bash
   grep -rE '\.padding\([0-9]|\.font\(\.system|Color\(red:|\.opacity\(0\.[0-9]' apps/AgeOS/Sources/Views/
   ```
6. Chạy app, đối chiếu từng màn với hành vi trước khi sửa — không được mất chức năng nào.

## Success Criteria

- [x] Grep literal spacing/font/color trong 4 file trả về rỗng
- [x] Library mỗi dòng hiện nguồn + token ước tính + số agent đang bật
- [x] Library filter là một `Menu` ba chiều, không phải toggle đơn
- [~] Target Matrix: dòng có ≥1 target bật được tint nền phân biệt rõ — code có tint + chỉ báo hình dạng không phụ thuộc màu, nhưng **chưa kiểm chứng bằng mắt** là đủ phân biệt
- [x] Target Matrix: mode và verified hiện trên header cột, không chỉ trong tooltip
- [x] Budget: top skills có % của tổng; disclaimer ở cuối màn
- [x] MCP: tách nhóm Enabled / Available
- [~] Mọi hành vi cũ còn nguyên: thêm nguồn, sync, toggle skill, toggle MCP, health check — chưa chạy tay được; xem kết quả regression hunt của code review
- [x] `swift test` xanh

## Risk Assessment

**Rủi ro: tính token cho mọi dòng làm chậm cuộn Library.** Công thức rẻ (`(name.count + desc.count + 30) / 4`) nhưng gọi mỗi lần render row thì vẫn phí.
*Tín hiệu:* cuộn giật với library lớn.
*Phản ứng đã định:* tính một lần khi `model.skills` đổi, cache vào một `[String: Int]` trên `AppModel`, row chỉ tra bảng.

**Rủi ro: tint nền dòng không đủ tương phản khi bật Increase Contrast**, hoặc quá đậm làm chữ khó đọc.
*Tín hiệu:* kiểm tra thủ công ở Phase 9.
*Phản ứng đã định:* nếu tint không đủ thì bổ sung tín hiệu thứ hai không phụ thuộc màu (ví dụ dấu chỉ báo ở đầu dòng) — không dựa duy nhất vào màu để truyền trạng thái.

**Rủi ro: mất chức năng khi viết lại.** 4 màn này đang chạy đúng; viết lại là cơ hội làm hỏng.
*Tín hiệu:* bước 6 phát hiện lệch.
*Phản ứng đã định:* làm từng màn một, mỗi màn một commit, đối chiếu hành vi ngay sau khi sửa xong màn đó — không viết lại cả 4 rồi mới kiểm.
