---
phase: 3
title: "Phase 3: Skills Distribution"
status: done
priority: P1
effort: "4d"
dependencies: [1, 2]
---

# Phase 3: Skills Distribution

## Overview
Adapter data-driven + link engine: enable/disable skill per agent (global/project), symlink với copy-fallback theo capability đo ở Phase 1, doctor sửa drift. Đây là trái tim "cài 1 nơi, dùng mọi agent".

## Requirements
- Functional: `ageos enable <skill> --target <agent> [--project <dir>]`, `disable`, `targets list`, `doctor [--fix]`; adapter bundled: claude-code, codex, universal-agents (`~/.agents/skills`), grok, antigravity (skills), claude-desktop (đánh dấu mcp-only); user override adapter trong `~/.ageos/adapters/`.
- Non-functional: mọi thao tác idempotent + revert được; không bao giờ ghi đè file user tự tạo trùng tên (phát hiện → dừng + báo); copy mode có hash manifest để sync/drift-detect.

## Architecture
- Adapter JSON schema v1: `{id, displayName, detect:[paths], skills:{globalPath, projectPath, folderSymlink:bool, fileSymlink:bool, preferredMode:symlink|copy, verified:bool}, mcp:{configPath, format:json|toml, keyPath, verified}, notes}`.
- Grok (tư vấn đã chốt): primary `~/.grok/skills`, `verified` từ spike; nếu spike cho thấy đọc `~/.agents/skills` thì universal adapter cover — flip chỉ là sửa JSON.
- LinkEngine: enable = link/copy từ `library/.../current`; version swap atomic → mọi target ăn theo; disable gỡ đúng link/copy do AgeOS tạo (nhận diện qua lockfile + xattr `dev.ageos.managed`).
- Doctor: broken link, orphan (lockfile mất entry), copy hash lệch, path agent biến mất, user file che skill.

## Related Code Files
- Create: `adapters/*.json` (kebab-case), `Sources/AgeOSCore/adapters/**` (AdapterSpec, AdapterRegistry), `Sources/AgeOSCore/link-engine/**` (LinkEngine, CopySync, ManagedMarker), `Sources/AgeOSCore/doctor/**`, CLI subcommands, `Tests/**` (fixture fake home per agent)
- Modify: `Lockfile` (targets state), `Index`

## Implementation Steps
1. Định nghĩa AdapterSpec + loader (bundle → `~/.ageos/adapters` override; validate schema, version field).
2. Điền adapter JSON từ ma trận spike (giá trị `verified:false` cho agent chưa đo).
3. LinkEngine symlink mode + ManagedMarker (xattr + lockfile) để chỉ gỡ thứ mình tạo.
4. Copy mode: copy + `.ageos-manifest.json` (hash từng file); sync khi version đổi; detect drift (user sửa tay → cảnh báo, không ghi đè khi chưa `--force`).
5. Scope project: ghi vào `<project>/.claude/skills` v.v.; tôn trọng walk-up (Codex/Grok) bằng cách link tại root project.
6. Doctor + `--fix` (re-link, re-copy, dọn orphan); output bảng + `--json`.
7. E2E test trên fake home: enable → verify path; đổi version → swap lan đúng; disable sạch.

## Todo
- [x] AdapterSpec + registry + override (user `~/.ageos/adapters/` thắng theo id; includeBundled=false cho test)
- [x] 6 adapter bundled điền số liệu spike (bundle qua SPM resources, root `adapters` symlink vào specs)
- [x] LinkEngine symlink + ManagedMarker (xattr dev.ageos.managed, XATTR_NOFOLLOW cho chính symlink)
- [x] Copy mode + `.ageos-manifest.json` hash + drift detect (sync tôn trọng drift, không đè khi chưa --force/--fix)
- [x] Scope project (link tại project root theo projectPath adapter) + idempotent re-enable
- [x] Doctor `--fix`: re-link, re-copy (in rõ khi đè), dọn orphan, user-shadow chỉ báo không đụng; fix lỗi canonical-path (/var vs /private/var) suýt gây xóa nhầm
- [x] E2E fake-home tests (10 test mới; tổng 32 xanh)

## Success Criteria
- [x] Enable 1 skill cho claude-code (symlink) + codex (copy) từ cùng version — VERIFIED MÁY THẬT (algorithmic-art; Claude Code hot-load ngay trong session đang chạy, grok thấy qua compat path); update version → cả hai nhận bản mới (unit test)
- [x] Disable không đụng file user; user file trùng tên → dừng + thông báo (unit test + disable thật sạch, lockfile về 0)
- [x] `ageos doctor` phát hiện + sửa: link gãy/missing target, copy drift, orphan; user-shadow được báo và KHÔNG bị đụng
- [x] Thêm 1 agent mới CHỈ bằng file JSON — test brand-new-agent pass

## Risk Assessment
- Agent đổi path sau release → signal: doctor báo path không tồn tại hàng loạt; response: cập nhật adapter JSON (data update, có thể fetch từ repo OSS), không cần app release.
- Codex không nhận file-symlink (đã biết) → mặc định copy mode cho codex; signal upstream fix: issue #8369 đóng; response: flip preferredMode.
- Xattr bị strip (backup/sync tool) → signal: marker mất nhưng lockfile còn; response: lockfile là nguồn chính, xattr chỉ là lớp phụ.
