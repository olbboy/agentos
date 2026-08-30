---
title: "Phase 3: Core Strings English"
status: done
phase: 3
priority: P1
effort: "1d"
dependencies: []
---

# Phase 3: Core Strings English

## Overview

Chuyển mọi chuỗi **hiển thị cho người dùng** trong `AgeOSCore`, `AgeOSCLI`, `AgeOSMCPServer` sang tiếng Anh. Không đổi hành vi, không đổi shape dữ liệu, không đổi schema `--json`.

Phase này độc lập với Phase 1–2, chạy song song được.

## Requirements

- Functional: `AgeOSError.message` + `.remedy`, `Doctor.Finding.message`, `BudgetMeter.Report.warnings`, lint/deprecated reason, và mọi output prose của CLI đều tiếng Anh.
- Functional: `AgeOSError.Code` (`.notFound`, `.invalidSkill`, …) giữ nguyên tên case — chúng là contract, không phải text hiển thị.
- Non-functional: schema `--json` không đổi (tên field, kiểu, cấu trúc). Chỉ nội dung chuỗi bên trong đổi.
- Non-functional: comment tiếng Việt trong code **giữ nguyên** — đây là ghi chú cho maintainer, không phải UI.

## Architecture

**Vì sao dịch trực tiếp chứ không dựng i18n cho core:** core hiện không có hạ tầng đa ngôn ngữ, và thêm vào sẽ phải thiết kế lại `AgeOSError` + `Doctor.Finding` thành mã lỗi + tham số, kéo theo CLI và MCP server. Đó là option "core phát error code" đã bị loại ở lúc lập plan vì over-engineering cho công cụ một maintainer. Ở đây chỉ đổi nội dung chuỗi.

**Ranh giới rõ ràng — cái gì đổi, cái gì không:**

| Đổi | Không đổi |
|---|---|
| `AgeOSError(.code, "message")` — phần message | `.code` — tên case enum |
| `remedy: "..."` | Tên field trong JSON |
| `Doctor.Finding.message` | `Doctor.Finding.Kind` raw value (`"broken_link"`, …) |
| `warnings.append("...")` | Cấu trúc `Report` |
| Prose in ra stdout của CLI | Format `--json` |
| Chuỗi trong test assert | Comment `///` và `//` tiếng Việt |

Phân bố đã verify: 60 `AgeOSError` call site, ~9 `Doctor.Finding.message`, 3 `BudgetMeter warnings.append`, ~8 lint/deprecated reason, cộng prose của CLI. 20 assertion trong test đang khớp chuỗi tiếng Việt.

**Lưu ý dịch:** giữ nguyên phần trong backtick (tên lệnh, path, id) — đó là dữ liệu, không phải văn xuôi. Ví dụ:
```swift
// Trước
throw AgeOSError(.notFound, "Nguồn '\(sourceId)' chưa được add",
                 remedy: "Xem `ageos source list`; add bằng `ageos source add <url|path>`")
// Sau
throw AgeOSError(.notFound, "Source '\(sourceId)' has not been added",
                 remedy: "Run `ageos source list`; add one with `ageos source add <url|path>`")
```

## Related Code Files

- Modify: `Sources/AgeOSCore/**/*.swift` (~81 chuỗi UI-reachable trên các file: `SyncEngine.swift`, `skill-model/SkillParser.swift`, `doctor/Doctor.swift`, `intelligence/BudgetMeter.swift`, `intelligence/ScanEngine.swift`, `link-engine/`, `sources/`, `mcp/`, `config-writers/`)
- Modify: `Sources/AgeOSCLI/**/*.swift` (prose output)
- Modify: `Sources/AgeOSMCPServer/**/*.swift` (mô tả tool + message lỗi)
- Modify: `Tests/**/*.swift` (20 assertion khớp chuỗi tiếng Việt)

## Implementation Steps

1. Liệt kê đầy đủ trước khi sửa:
   ```bash
   grep -rn '"[^"]*[àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ][^"]*"' --include="*.swift" Sources/ > /tmp/vi-strings.txt
   ```
   Rà tay danh sách, đánh dấu dòng nào là chuỗi UI, dòng nào chỉ là comment lọt vào (grep bắt cả comment có dấu nháy).
2. Dịch theo module, mỗi module một commit: `AgeOSCore` → `AgeOSCLI` → `AgeOSMCPServer`. Commit nhỏ để dễ review và dễ lùi.
3. Sau mỗi module, chạy `swift test`; sửa assertion vỡ **cùng commit** với chuỗi gây vỡ — đừng để test đỏ vắt qua nhiều commit.
4. Xác minh schema `--json` không đổi: chạy vài lệnh có `--json` trước và sau, so cấu trúc (không so nội dung chuỗi):
   ```bash
   ageos scan --json | jq 'paths(scalars) | join(".")' | sort -u > /tmp/json-keys-after.txt
   ```
   Diff với bản chụp trước khi sửa. Khác biệt duy nhất được phép là nội dung chuỗi, không phải key.
5. Kiểm tra sót:
   ```bash
   grep -rn '"[^"]*[àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ][^"]*"' --include="*.swift" Sources/
   ```
   Kết quả phải rỗng (comment không dùng dấu nháy nên không lọt).

## Success Criteria

- [x] Grep chuỗi tiếng Việt trong string literal ở `Sources/` trả về rỗng
- [x] Comment tiếng Việt còn nguyên (không bị dịch nhầm)
- [x] `AgeOSError.Code` và `Doctor.Finding.Kind` raw value không đổi
- [x] Key của output `--json` không đổi (diff `jq paths` trước/sau chỉ khác nội dung chuỗi)
- [x] 20 test assertion đã cập nhật, `swift test` xanh
- [x] Chạy thử `ageos doctor`, `ageos scan`, `ageos budget` trên máy thật — output tiếng Anh, đọc tự nhiên

## Risk Assessment

**Rủi ro: dịch lọt vào comment hoặc vào phần dữ liệu trong backtick.**
*Tín hiệu:* comment `///` thành tiếng Anh, hoặc tên lệnh trong backtick bị đổi (`ageos source add` → "add source").
*Phản ứng đã định:* review diff theo từng file, không dùng sed hàng loạt. Backtick là ranh giới cứng: nội dung bên trong không bao giờ đổi.

**Rủi ro: có consumer đang grep prose output của CLI.**
*Tín hiệu:* script CI hoặc README hướng dẫn `ageos ... | grep "<chữ tiếng Việt>"`.
*Phản ứng đã định:* grep README + scripts + `.github/` trước khi sửa. Nếu có thì chuyển sang `--json` + `jq` — grep trên prose vốn đã là cách dùng không an toàn.

**Rủi ro: schema `--json` vô tình đổi** vì chuỗi được dùng làm key ở đâu đó.
*Tín hiệu:* diff `jq paths` ở bước 4 khác nhau về key.
*Phản ứng đã định:* dừng, tìm chỗ chuỗi bị dùng làm key, giữ nguyên key và chỉ đổi phần hiển thị.
