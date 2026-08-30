---
title: "docs/ sang tiếng Anh + sửa nội dung lỗi thời"
description: "Dịch 4 file docs còn tiếng Việt sang tiếng Anh, đồng thời sửa những chỗ đã lệch so với code sau bản redesign UI. Không phải job dịch thuần — nội dung đang sai."
status: pending
priority: P2
effort: "0.5d"
tags: [ageos, docs, i18n]
created: 2026-08-30
---

# docs/ sang tiếng Anh + sửa nội dung lỗi thời

## Overview

`README.md`, `CONTRIBUTING.md`, `SECURITY.md` và `docs/design-guidelines.md` viết
bằng tiếng Anh. Bốn file còn lại trong `docs/` viết bằng tiếng Việt. Sau khi
[bản redesign UI](../260830-0851-ageos-ui-redesign/plan.md) chuyển toàn bộ app,
core và CLI sang tiếng Anh, `docs/` là bề mặt duy nhất còn trộn ngôn ngữ.

**Đây không phải job dịch thuần.** Scout cho thấy nội dung đã lệch so với code:

| Chỗ | Đang ghi | Thực tế |
|---|---|---|
| `codebase-summary.md:32` | `Views/ (Library, TargetMatrix, Budget, Scan, Adopt, Mcp)` | `Scan` và `Adopt` đã bị xoá; giờ là `Overview`, `Diagnostics`, `MenuBar`, `Settings` |
| `codebase-summary.md:29` | `68 test / 23 suite` | 69 test / 23 suite |
| `codebase-summary.md:46` | `68 tests xanh`, `App: build xanh + 3 unit tests` | 69 core; app 24 test / 5 suite |
| `deployment-guide.md:14` | `swift test  # 68 tests` | 69 tests |

Dịch mà bê nguyên những con số sai này sang tiếng Anh là làm cho nợ kỹ thuật khó
thấy hơn, không phải trả nó.

## Goals

| # | Goal | Priority |
|---|------|----------|
| 1 | 4 file `docs/` viết bằng tiếng Anh, đọc tự nhiên (không dịch word-by-word) | P2 |
| 2 | Mọi số liệu và tên file trong docs khớp code tại thời điểm sửa, đã verify bằng lệnh | P1 |
| 3 | Mọi lệnh trong `deployment-guide.md` chạy được thật, không phải chép lại | P1 |
| 4 | Link nội bộ và link từ README/CONTRIBUTING không gãy | P2 |

## Phases

| # | Phase | Status |
|---|-------|--------|
| 1 | [Phase 1: Mô tả hiện trạng](./phase-01-describe-reality.md) | Pending |
| 2 | [Phase 2: Quy trình chạy được](./phase-02-verifiable-procedures.md) | Pending |

Ranh giới giữa hai phase là **cách kiểm chứng**, không phải kích thước:

- Phase 1 (`codebase-summary.md`, `system-architecture.md`) mô tả code. Kiểm bằng
  cách đối chiếu với cây file và output test thật.
- Phase 2 (`deployment-guide.md`, `project-overview-pdr.md`) chứa quy trình và
  cam kết sản phẩm. Kiểm bằng cách **chạy** lệnh trong đó.

Hai phase độc lập, làm song song được.

## Constraints

- Giữ nguyên cấu trúc heading và thứ tự mục của từng file — đây là bản dịch kèm
  sửa số liệu, không phải viết lại tài liệu.
- Không đụng `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `docs/design-guidelines.md`
  (đã tiếng Anh).
- Nội dung trong backtick (lệnh, path, id) giữ nguyên, không dịch.
- Mỗi số liệu đưa vào docs phải đến từ một lệnh chạy được, ghi rõ lệnh đó trong
  báo cáo. Không chép số từ file cũ.
- `docs.maxLoc` của dự án là 800 dòng/file — cả 4 file đang dưới 60 dòng, giữ vậy.

## Non-goals

- Không dịch ngược sang tiếng Việt, không dựng hạ tầng đa ngôn ngữ cho docs.
- Không dịch comment tiếng Việt trong code — đó là ghi chú cho maintainer, và bản
  redesign UI đã cố ý giữ chúng.
- Không viết thêm tài liệu mới. Nếu phát hiện thiếu mục nào, ghi vào Open Questions
  chứ không tự thêm.
- Không đụng `plans/` cũ — chúng là bản ghi trạng thái tại thời điểm đó, không
  phải tài liệu evergreen.

## Success Criteria

- [ ] `grep -rn '[diacritics + CHỮ HOA]' docs/` không còn khớp trong 4 file
      (dùng character class có **cả chữ hoa** — bản redesign đã vấp đúng lỗi
      character class chỉ có chữ thường và để sót `"fix THẤT BẠI"`)
- [ ] Quét thêm tiếng Việt **không dấu** bằng danh sách từ vựng, không chỉ dựa
      vào dấu
- [ ] `codebase-summary.md` liệt kê đúng tên file view hiện có, đối chiếu bằng
      `find apps/AgeOS/Sources -name '*.swift'`
- [ ] Mọi con số test trong docs khớp output thật của `swift test` và
      `xcodebuild test`
- [ ] Mọi lệnh trong `deployment-guide.md` đã được chạy hoặc ghi rõ lý do không
      chạy được (ví dụ cần credential phát hành)
- [ ] Link trong README và CONTRIBUTING trỏ tới 4 file này vẫn mở được
- [ ] `swift build && swift test` xanh (docs không đụng code, đây là kiểm tra
      rằng đúng là không đụng)

## Open Questions

1. `project-overview-pdr.md` là tài liệu định vị sản phẩm — dịch nó có làm mất
   sắc thái nào không, hay nên viết lại bằng tiếng Anh từ đầu thay vì dịch? Quyết
   định ở bước 1 của Phase 2, sau khi đọc kỹ file.
2. Sau khi 4 file này sang tiếng Anh, `docs/` sẽ thuần tiếng Anh nhưng comment
   trong code vẫn tiếng Việt. Đó là chủ ý (maintainer note), nhưng nếu về sau có
   contributor ngoài thì cần quyết định lại — ngoài phạm vi plan này.

<!-- slug: docs-english -->
