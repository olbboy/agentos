---
title: "Phase 2: Quy trình chạy được"
status: todo
phase: 2
priority: P1
effort: "0.25d"
dependencies: []
---

# Phase 2: Quy trình chạy được

## Overview

`deployment-guide.md` chứa quy trình phát hành. `project-overview-pdr.md` chứa
định vị sản phẩm. Hai loại nội dung khác nhau, nhưng cùng một tiêu chuẩn kiểm
chứng: **lệnh phải chạy được, cam kết phải đúng**.

Độc lập với Phase 1, làm song song được.

## Requirements

- Functional: hai file viết bằng tiếng Anh, giữ nguyên cấu trúc heading.
- Functional: mọi lệnh trong `deployment-guide.md` đã chạy thật, hoặc ghi rõ vì
  sao không chạy được.
- Non-functional: cam kết trong PDR không hứa thứ code không làm.

## Architecture

**Vì sao deployment-guide đáng một tiêu chuẩn cao hơn:** nó được đọc đúng lúc
người ta đang phát hành, khi sai một lệnh là tốn thời gian thật. `CONTRIBUTING.md`
trỏ thẳng vào nó cho maintainer. Một lệnh chép lại mà chưa từng chạy là bẫy.

**Lệnh nào chạy được, lệnh nào không:**

| Loại | Ví dụ | Kiểm thế nào |
|---|---|---|
| Build / test | `swift test` | Chạy thật |
| Đọc trạng thái | `git tag`, `gh release list` | Chạy thật |
| Phát hành | tag, upload, cập nhật cask | **Không chạy** — ghi rõ là bước một chiều, kiểm bằng cách đối chiếu với `scripts/release-lane.sh` |

Dòng đã biết là sai: `deployment-guide.md:14` ghi `swift test  # 68 tests`, thực
tế 69.

**PDR:** đây là tài liệu định vị, không phải mô tả kỹ thuật. Bước 1 phải quyết
định dịch hay viết lại — dịch word-by-word một tài liệu định vị thường ra thứ đọc
như bản dịch máy. Quyết định đó ghi vào plan, không tự làm im lặng.

## Related Code Files

- Modify: `docs/deployment-guide.md`
- Modify: `docs/project-overview-pdr.md`
- Read (nguồn sự thật): `scripts/release-lane.sh`, `packaging/`, `Package.swift`

## Implementation Steps

1. Đọc `project-overview-pdr.md`. Quyết định **dịch** hay **viết lại bằng tiếng
   Anh từ đầu**, ghi lý do. Nếu viết lại thì vẫn giữ nguyên các cam kết sản phẩm,
   không nhân cơ hội đổi định vị.
2. Với `deployment-guide.md`: liệt kê mọi lệnh, phân loại theo bảng trên.
3. Chạy nhóm "build/test" và "đọc trạng thái". Ghi output thật.
4. Với nhóm "phát hành": đối chiếu từng bước với `scripts/release-lane.sh`. Lệnh
   nào trong docs mà script không có (hoặc ngược lại) là một khác biệt cần giải
   thích, không phải bỏ qua.
5. Viết lại cả hai file bằng tiếng Anh, dùng số và output vừa thu được.
6. Quét sót bằng **hai tầng** grep như Phase 1 (có chữ hoa, có từ không dấu).
7. Xác nhận link từ `CONTRIBUTING.md:71` và `README.md:98` vẫn mở được.

## Success Criteria

- [ ] Hai file hoàn toàn tiếng Anh, cả hai tầng grep đều rỗng
- [ ] Mọi lệnh build/test trong `deployment-guide.md` đã chạy, output khớp docs
- [ ] Bước phát hành một chiều được đánh dấu rõ là chưa chạy, kèm lý do
- [ ] Khác biệt giữa `deployment-guide.md` và `scripts/release-lane.sh` hoặc đã
      được hoà giải, hoặc ghi rõ vì sao khác
- [ ] Quyết định "dịch hay viết lại" PDR được ghi lại kèm lý do
- [ ] Link từ README và CONTRIBUTING mở được

## Risk Assessment

**Rủi ro: chép lại lệnh phát hành mà chưa từng chạy**, rồi nó sai vào đúng lúc
người ta cần nó nhất.
*Tín hiệu:* bước 4 thấy docs và `release-lane.sh` lệch nhau.
*Phản ứng đã định:* script là nguồn sự thật (nó chạy thật), docs phải theo. Nếu
docs mô tả bước mà script không có thì hoặc script thiếu, hoặc docs thừa — phải
kết luận rõ, không viết mập mờ cho qua.

**Rủi ro: dịch PDR làm mất sắc thái định vị**, ra một bản tiếng Anh nhạt hơn bản
gốc.
*Tín hiệu:* đọc lại thấy như bản dịch máy.
*Phản ứng đã định:* đó là lý do bước 1 cho phép **viết lại** thay vì dịch. Cam kết
sản phẩm giữ nguyên, cách diễn đạt được tự do.
