---
phase: 7
title: "Phase 7: OSS Release"
status: done
priority: P2
effort: "3d"
dependencies: [6]
---

# Phase 7: OSS Release

## Overview
Đưa AgeOS ra công khai đúng chuẩn OSS: license, docs, CI, đóng gói + notarize lane, Homebrew cask, tag v0.1.0.

## Requirements
- Functional: repo GitHub public; LICENSE MIT; README (EN, có quickstart CLI + screenshot app); CONTRIBUTING.md kèm **guide thêm adapter bằng JSON PR** (con đường contribution chính); SECURITY.md (lập trường supply-chain: không auto-execute, scan, backup config); docs evergreen trong `docs/`; CI build+test+lint; GitHub Releases (zip app + tarball CLI) + Homebrew tap/cask; Sparkle appcast (chỉ khi có Developer ID).
- Non-functional: không secrets trong repo/CI; release có SHA-256 checksums; bản chưa ký phải có hướng dẫn `xattr -dr com.apple.quarantine` rõ ràng.

<!-- Updated: Validation Session 1 - LICENSE MIT xác nhận -->

## Architecture
- CI GitHub Actions: job `swift build/test` + SwiftFormat/SwiftLint trên image macOS 26 (fallback: image mới nhất có Xcode 26; nếu chưa có → self-hosted note, không block merge bằng job app).
- Release lane script: build Release, codesign (Developer ID nếu có secret), `notarytool submit`, staple, dmg/zip, checksums, cask bump.
- Bundle id placeholder `io.github.<owner>.ageos` — chốt khi tạo repo public.
- Docs (theo convention dự án): `docs/project-overview-pdr.md`, `docs/system-architecture.md`, `docs/codebase-summary.md`, `docs/deployment-guide.md` (release lane).

## Related Code Files
- Create: `LICENSE`, `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `scripts/release-lane.sh`, `docs/*.md`, cask formula (tap repo riêng)
- Modify: `README` badges, `Package.swift` metadata

## Implementation Steps
1. LICENSE MIT + headers tối thiểu; audit deps license (toàn bộ đã chọn đều permissive — verify).
2. README: pitch (1 source of truth + budget + security), quickstart, ma trận agent hỗ trợ + trạng thái `verified`.
3. CONTRIBUTING: dev setup, test, **adapter-json guide** (schema + checklist verify), code style.
4. SECURITY.md + threat model tóm tắt (từ advisory).
5. docs/ evergreen 4 file (≤800 dòng/file), link từ README.
6. CI: build/test/lint + cache SPM; release workflow tag-triggered.
7. Release lane script (ký + notarize có điều kiện secret; fallback unsigned + quarantine note).
8. Homebrew tap + cask; cài thử máy sạch.
9. Tag `v0.1.0`, GitHub Release notes (đối chiếu Success Criteria plan.md).

## Todo
- [x] LICENSE MIT + README EN (pitch/quickstart/ma trận verified) + CONTRIBUTING (adapter-JSON guide + checklist verify) + SECURITY (threat model 6 điểm); deps audit: toàn bộ MIT/Apache-2.0/BSD — 0 copyleft
- [x] docs/ 4 file evergreen (<800 dòng): pdr, system-architecture, codebase-summary, deployment-guide
- [x] CI workflow (core required + app job continue-on-error, cache SPM, macos-26 với fallback note) — XANH TRÊN GITHUB cần push (chưa publish)
- [x] Release lane script: CLI tarball + app zip + ký/notarize CHỈ KHI có AGEOS_SIGN_IDENTITY/AGEOS_NOTARY_PROFILE, fallback unsigned + quarantine note + SHA-256 checksums
- [x] Cask template packaging/homebrew/ageos.rb (điền owner/sha khi có tap) — cài máy sạch verify SAU khi publish
- [ ] v0.1.0 + release notes — CHẶN BỞI QUYẾT ĐỊNH USER: chốt GitHub owner/bundle id, tạo repo public (secret-scan trước), tap repo, (tùy chọn) Developer ID

## Success Criteria
- [ ] Máy sạch cask install — SAU PUBLISH (artifacts + lane sẵn sàng)
- [ ] CI xanh trên push + PR — SAU PUBLISH (workflow sẵn sàng; core suite xanh local 62/62)
- [x] Repo chưa có commit nào (git init sạch) — secret-scan chạy trước commit đầu khi user quyết định publish; .gitignore chặn .build/xcodeproj/DS_Store
- [x] Acceptance plan.md: 7/8 tick với bằng chứng máy thật, mục #8 (repo public) chờ user — xem plan.md

## Risk Assessment
- Chưa có Apple Developer ID ($99/năm, quyết định cá nhân) → signal: thiếu secret ký; response: phát hành unsigned + hướng dẫn quarantine + cask `--no-quarantine` note; Sparkle hoãn (yêu cầu ký) — KHÔNG block v0.1.0.
- GitHub Actions chưa có image macOS 26 → signal: setup-xcode fail; response: dùng image mới nhất có Xcode 26 beta hoặc tách job app khỏi required checks, core package vẫn test được.
- Tên "AgeOS" đụng thương hiệu khác khi public → signal: khiếu nại/nhầm lẫn; response: user đã chốt AgeOS; nếu phát sinh xung đột pháp lý thì đổi tên hiển thị, giữ bundle id trung tính.
