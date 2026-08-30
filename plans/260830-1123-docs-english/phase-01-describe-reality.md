---
title: "Phase 1: Mô tả hiện trạng"
status: todo
phase: 1
priority: P1
effort: "0.25d"
dependencies: []
---

# Phase 1: Mô tả hiện trạng

## Overview

`codebase-summary.md` và `system-architecture.md` mô tả code. Chúng vừa viết bằng
tiếng Việt vừa mô tả một cấu trúc không còn tồn tại. Phase này sửa cả hai.

## Requirements

- Functional: hai file viết bằng tiếng Anh, giữ nguyên cấu trúc heading.
- Functional: mọi tên file, tên module, số liệu khớp code tại thời điểm sửa.
- Non-functional: mỗi con số đưa vào phải đến từ một lệnh chạy được.

## Architecture

**Vì sao không dịch trước rồi sửa số sau:** dịch một câu sai chỉ tạo ra câu sai
bằng tiếng Anh, và lúc đó khó thấy nó sai hơn vì đọc trôi chảy. Thứ tự đúng là
**xác minh trước, dịch sau** — với mỗi đoạn, chạy lệnh kiểm tra rồi mới viết lại.

**Chỗ đã biết là sai** (scout 2026-08-30, sau bản redesign UI):

| File:dòng | Đang ghi | Cần kiểm bằng |
|---|---|---|
| `codebase-summary.md:29` | `68 test / 23 suite` | `swift test` |
| `codebase-summary.md:32` | `Views/ (Library, TargetMatrix, Budget, Scan, Adopt, Mcp)` | `find apps/AgeOS/Sources/Views -name '*.swift'` |
| `codebase-summary.md:46` | `68 tests xanh`, `App: build xanh + 3 unit tests` | `swift test`, `xcodebuild test -only-testing:AgeOSTests` |

Danh sách này **không đầy đủ** — nó là những chỗ scout tìm ra trong một lượt quét
nhanh. Bước 1 phải rà toàn bộ, không chỉ sửa 3 dòng này.

## Related Code Files

- Modify: `docs/codebase-summary.md`
- Modify: `docs/system-architecture.md`
- Read (nguồn sự thật): `apps/AgeOS/Sources/`, `Sources/`, output `swift test`

## Implementation Steps

1. Đọc cả hai file. Với **mỗi** phát biểu về code (tên file, số lượng, module,
   luồng dữ liệu), ghi ra lệnh sẽ dùng để kiểm. Chưa sửa gì ở bước này.
2. Chạy toàn bộ lệnh đó, ghi kết quả thật.
3. Viết lại từng đoạn bằng tiếng Anh, dùng số vừa đo. Giữ nguyên thứ tự heading.
4. Quét sót bằng **hai** tầng:
   ```bash
   # tầng 1: dấu tiếng Việt, CÓ CẢ CHỮ HOA
   grep -n '[àáảãạ…đÀÁẢÃẠ…Đ]' docs/codebase-summary.md docs/system-architecture.md
   # tầng 2: tiếng Việt không dấu
   grep -niE '\b(cho|vd|xem|khi|cua|voi|khong|duoc|neu|hoac|theo|sau|truoc)\b' docs/*.md
   ```
   Bản redesign UI đã vấp đúng chỗ này: character class chỉ có chữ thường nên để
   sót `"fix THẤT BẠI"`, và grep theo dấu bỏ qua hoàn toàn `"sau centering"`.
5. Mở link trong file, xác nhận không gãy.

## Success Criteria

- [ ] Hai file hoàn toàn tiếng Anh, cả hai tầng grep đều rỗng
- [ ] Danh sách file trong `codebase-summary.md` khớp `find` thật, không còn
      `Scan`/`Adopt`
- [ ] Mọi con số khớp output lệnh, ghi rõ lệnh nào cho ra số nào
- [ ] Cấu trúc heading không đổi
- [ ] Link nội bộ mở được

## Risk Assessment

**Rủi ro: dịch xong vẫn còn phát biểu sai mà không ai phát hiện**, vì tiếng Anh
trôi chảy che được nội dung sai.
*Tín hiệu:* bước 1 bỏ qua một phát biểu vì "nhìn có vẻ đúng".
*Phản ứng đã định:* bước 1 bắt buộc liệt kê lệnh kiểm cho **mọi** phát biểu về
code trước khi sửa dòng nào. Phát biểu nào không nghĩ ra cách kiểm thì ghi vào
Open Questions, không im lặng bê nguyên.

**Rủi ro: số liệu lại lệch ngay sau khi sửa** vì code tiếp tục đổi.
*Tín hiệu:* có PR khác đang mở chạm vào cùng vùng.
*Phản ứng đã định:* chấp nhận. Docs mô tả trạng thái tại một thời điểm; giải pháp
thật là sinh số tự động, nhưng đó là plan khác.
