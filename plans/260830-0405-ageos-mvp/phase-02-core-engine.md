---
phase: 2
title: "Phase 2: Core Engine"
status: done
priority: P1
effort: "3d"
dependencies: []
---

# Phase 2: Core Engine

## Overview
Scaffold repo + core: store `~/.ageos/` version hóa, nguồn GitHub/local, parser SKILL.md, lockfile nhớ install-mode, index SQLite, CLI khung. Filesystem là source of truth; SQLite chỉ là cache rebuild được.

## Requirements
- Functional: `ageos source add|list|sync`, `ageos list`, fetch GitHub tarball (không cần git), parse + validate SKILL.md, store content-addressed theo version, lockfile `ageos.lock.json` (version + linkMode per target), index rebuild (`ageos reindex`).
- Non-functional: mọi path store qua env `AGEOS_HOME` (test không đụng home thật); offline sau sync (ETag cache); Swift 6 strict concurrency; module hóa rõ.

## Architecture
- SPM package: lib `AgeOSCore` (modules nội bộ: `Store`, `Sources`, `SkillModel`, `Lockfile`, `Index`), executable `ageos` (swift-argument-parser).
- Store: `~/.ageos/library/skills/<source-ns>/<name>/<version>/` + symlink `current`; `index.sqlite` (GRDB); `backups/`; `adapters/`.
- `SourceProvider` protocol → `GitHubSource` (tarball API, ETag, archived flag), `LocalSource`. Namespace `owner/repo/skill` chống trùng tên.
- Parser: Yams (frontmatter) + swift-markdown (body), validate theo spec agentskills.io.
- Dependencies: GRDB, Yams, swift-markdown, swift-argument-parser (thêm TOMLKit ở Phase 4).

## Related Code Files
- Create: `Package.swift`, `Sources/AgeOSCore/**` (store/, sources/, skill-model/, lockfile/, index/ — file Swift PascalCase), `Sources/AgeOSCLI/**`, `Tests/AgeOSCoreTests/**` + `Tests/Fixtures/**`

## Implementation Steps
1. `swift package init` + products (`AgeOSCore`, `ageos`) + deps; CI-ready `swift build && swift test`.
2. `SkillModel` + parser + validator (golden tests từ fixtures: skill hợp lệ, thiếu field, frontmatter hỏng, unicode).
3. `Store`: layout, ghi atomic (temp + rename), version dir + `current` swap, GC version mồ côi.
4. `GitHubSource`: resolve repo → tarball ref (tag/sha), ETag cache, quét thư mục skill (kể cả repo multi-skill kiểu `anthropics/skills`), archived flag.
5. `Lockfile`: schema {source, name, version(sha/tag), targets: {agent: {scope, linkMode}}}; đọc/ghi ổn định (sorted keys, versioned schema).
6. `Index` GRDB: bảng skills/sources/versions; `reindex` rebuild từ FS.
7. CLI subcommands + `--json`; error message có hướng khắc phục.
8. Test: fake tarball fixtures + `AGEOS_HOME` tạm; coverage đường chính.

## Todo
- [x] Scaffold SPM + deps build xanh (GRDB 7, Yams, swift-markdown, swift-argument-parser; swift-tools 6.0, macOS 26)
- [x] Parser + validator SKILL.md (golden tests: valid/missing-name/broken-yaml/unicode/no-frontmatter; description >1024 hạ xuống warning vì agent thật vẫn load — bằng chứng anthropics/skills/claude-api 1068 chars)
- [x] Store + version swap atomic (`current` symlink, rename(2)) + GC orphan + sanitize version dir
- [x] GitHubSource tarball + ETag + sha compare + archived flag (mock HTTP tests)
- [x] Lockfile schema v1 (targets nhớ scope/linkMode/path, sorted stable JSON)
- [x] Index GRDB + reindex rebuild từ FS
- [x] CLI source add/list/sync/remove + list + reindex, `--json`, lỗi có remedy

## Success Criteria
- [x] `ageos source add https://github.com/anthropics/skills` → 20 skill @ 3b3fad96af16; sync lần 2 no-op (verified máy thật)
- [x] Xóa `index.sqlite` → `ageos reindex` khôi phục đúng 20 skill (verified CLI thật + unit test)
- [x] `swift test` xanh 22/22, mọi test qua `AGEOS_HOME` tạm — không đụng `$HOME` thật

## Risk Assessment
- Repo skill cấu trúc lạ (skill ở root vs nested) → signal: sync ra 0 skill dù repo có SKILL.md; response: scanner dò mọi `**/SKILL.md` độ sâu ≤4, log những gì bỏ qua.
- Rate-limit GitHub không token → signal: 403; response: hỗ trợ `GITHUB_TOKEN` env tùy chọn + backoff, thông báo rõ.
- Swift 6 concurrency chậm tiến độ → signal: quá 1 ngày chỉ vì lỗi Sendable; response: hạ xuống `@preconcurrency` cục bộ có chú thích, không hạ toolchain.
