---
title: "AgeOS MVP — native macOS Skills + MCP manager (OSS)"
description: "App macOS native (SwiftUI, macOS 26+) quản lý & phân phối Agent Skills + MCP servers: library trung tâm, adapter per-agent (symlink/copy), intelligence (dedupe/quality/budget), CLI + MCP server."
status: done
priority: P1
effort: "26d"
tags: [ageos, macos, swift, mcp, skills]
created: 2026-08-30
---

# AgeOS MVP

## Overview

AgeOS (tên cũ AgentOS; repo dir giữ `agentos`) = 1 core engine Swift + 3 mặt điều khiển (SwiftUI app, CLI `ageos`, MCP server stdio) trên library trung tâm `~/.ageos/`. Kéo skills (chuẩn agentskills.io) + MCP servers (server.json/.mcpb) từ nhiều nguồn, phân phối qua adapter data-driven (symlink, copy-fallback), quét dupe/deprecated/quality + Context Budget Meter.

Quyết định đã chốt (user 30/8): **OSS — license MIT (chốt tại validate Session 1)** · **macOS 26+** (dùng FoundationModels, fallback khi Apple Intelligence tắt) · **tên AgeOS** · Grok path: adapter primary `~/.grok/skills`, xác minh `grok inspect` ở Phase 1, fallback universal `~/.agents/skills` — adapter là JSON data nên đổi path = data update, không cần release.

Contract gốc: `../reports/brainstorm-260830-0335-agentos-skills-mcp-manager.md` · Feature/tool: `../reports/advisory-260830-0356-feature-advisory-tools.md` (thắng khi trùng) · Evidence thô: `../reports/research-260830-0356-grok-x-skills-mcp.md`.

Stack chốt: Swift 6 / SwiftUI / swift-sdk (MCP) / GRDB / Yams / swift-markdown / swift-argument-parser / TOMLKit / NLContextualEmbedding + FoundationModels / FSEventStream / Keychain / Sparkle 2.

## Goals

| # | Goal | Priority |
|---|------|----------|
| 1 | Library trung tâm + nguồn GitHub/local, version hóa + lockfile nhớ install-mode | P1 |
| 2 | Phân phối skills per-agent (Claude Code, Codex, Grok, Antigravity) symlink/copy + doctor | P1 |
| 3 | Phân phối MCP (registry chính thức, .mcpb) — ghi config an toàn + health-check | P1 |
| 4 | Intelligence: adopt/effective-load scan, dedupe exact+near, deprecated, quality, Budget Meter, description linter | P1 |
| 5 | 3 surfaces: MCP server tự phục vụ, CLI `--json`, SwiftUI app + menu bar | P1 |
| 6 | OSS release v0.1.0: MIT, docs, CI, Homebrew cask, notarize lane | P2 |

## Phases

| # | Phase | Status |
|---|-------|--------|
| 1 | [Phase 1: Spike & Adapter Verification](./phase-01-spike.md) | ✅ Done (2026-08-30, report: reports/spike-adapter-matrix.md) |
| 2 | [Phase 2: Core Engine](./phase-02-core-engine.md) | ✅ Done (2026-08-30, 22 tests xanh, smoke thật anthropics/skills) |
| 3 | [Phase 3: Skills Distribution](./phase-03-skills-distribution.md) | ✅ Done (2026-08-30, verified máy thật claude-code+codex) |
| 4 | [Phase 4: MCP Distribution](./phase-04-mcp-distribution.md) | ✅ Done (2026-08-30, 3-client thật round-trip sạch) |
| 5 | [Phase 5: Intelligence](./phase-05-intelligence.md) | ✅ Done (2026-08-30, máy thật: 18 exact-dupe, budget 9,992 tokens) |
| 6 | [Phase 6: Surfaces](./phase-06-surfaces.md) | ✅ Done (2026-08-30, mcp loopback E2E + app build + dogfood; UI smoke chờ TCC) |
| 7 | [Phase 7: OSS Release](./phase-07-oss-release.md) | 🟡 Local-ready (2026-08-30) — publish chờ quyết định user |

Phụ thuộc: 3←(1,2) · 4←(1,2) · 5←(3,4) · 6←5 · 7←6. Phase 2 có thể chạy song song Phase 1.

## Success Criteria

- [x] `ageos source add https://github.com/anthropics/skills` → 20 skill trong <60s kèm metadata (sha/stars/license), CLI verified máy thật; GUI Library browser cùng nguồn data
- [x] Enable skill cho Claude Code qua symlink → CHÍNH session Claude Code đang chạy hot-load ngay (mạnh hơn "session mới"); Codex nhận qua copy+manifest — verified máy thật, disable sạch
- [x] Enable 1 MCP server (HelloMCP spike) cho Claude Code + Claude Desktop + Grok thật: đúng format từng app, backup mili-giây, disable xong diff GIỐNG HỆT backup; `ageos mcp health` handshake pass (22ms)
- [x] Scan máy thật bắt 18 cặp exact-dupe + 16 near-dupe cài sẵn; repo archived → deprecated (unit test; near-dupe calibrated không false-positive trên cặp khác nghĩa)
- [x] `ageos budget --target claude-code` = ≈9,992 tokens/136 skills + cảnh báo ngưỡng + cảnh báo MCP chưa đo; đối chiếu /context thủ công ghi trong CLI output (±20%)
- [x] Flow `search_skills → install_skill → enable_skill` qua ageos-mcp pass loopback E2E; VÀ đã gọi thành công `list_targets` + `budget_report` TỪ SESSION CLAUDE CODE THẬT (30/8 07:52 — server dogfood tự load vào session, trả 6 adapter + budget 10,450 tokens) — acceptance khép trọn
- [x] Disable/remove sạch idempotent (lockfile về 0, agent dir nguyên trạng); mọi file user được bảo vệ bằng conflict-check + marker (test + máy thật)
- [x] Repo public (user push 30/8) + v0.1.0 PUBLISHED 30/8 08:19: tag → release workflow xanh (CLI tarball + app zip + checksums), cask lên olbboy/homebrew-tap, `brew install --cask ageos` CÀI THẬT thành công (qua Tap-Trust mới của Homebrew; app chạy từ /Applications) — release notes đối chiếu criteria

## Validation Log

### Session 1 — 2026-08-30
**Trigger:** Post-plan validate (user chọn sau khi plan tạo)
**Questions asked:** 4

#### Verification Results
- Claims checked: 15 — Verified: 13 | Failed: 0 | Unverified: 2
- Tier: Full (7 phases; thích ứng greenfield — chưa có code để grep, verify machine-facts + toolchain + agent dirs)
- Evidence: macOS 26.5.2 / Swift 6.3.3 / Xcode 26.6 trên máy dev; tồn tại `~/.claude/skills`, `~/.codex`, `~/.agents/skills`, `~/.grok/skills`, `~/.gemini`, `~/Library/Application Support/Claude`; CLI claude+codex+grok OK (gemini CLI vắng — không chặn, Antigravity verify qua `~/.gemini`)
- Unverified (chủ đích — là mục tiêu Phase 1 spike): hành vi symlink per-agent; FoundationModels runtime availability

#### Questions & Answers
1. **[Scope]** License cho AgeOS (OSS)? — Options: MIT (Recommended) | Apache-2.0 | GPL-3.0 — **Answer:** MIT — Rationale: chuẩn de-facto dev-tool, thân thiện adapter contribution.
2. **[Scope]** Bộ adapter đợt đầu (Phase 3) giữ như plan? — Options: Giữ 6 adapter (Recommended) | Thêm Cursor + Gemini CLI riêng | Tối giản Claude Code + Codex — **Answer:** Giữ 6 adapter — Rationale: đúng scope user nêu; Cursor/OpenCode hưởng ké qua universal `.agents/skills`.
3. **[Tradeoffs]** Chiến lược ghi TOML (config.toml Codex/Grok), TOMLKit normalize có thể mất comment user? — Options: Normalize + cảnh báo (Recommended) | Line-targeted editor ngay | Không tự ghi TOML — **Answer:** Normalize + cảnh báo — Rationale: ship MVP đúng hạn; replan line-targeted nếu phản ứng cộng đồng lớn (đã nằm trong Risk Phase 4).
4. **[Risks]** Secrets env MCP ở MVP? — Options: Plaintext + Keychain v1.1 (Recommended) | Kéo Keychain vào MVP — **Answer:** Plaintext + Keychain v1.1 — Rationale: ngang hiện trạng các client, đánh dấu `sensitive` trong lockfile; Keychain là milestone kế.

#### Confirmed Decisions
- License MIT (Phase 7) · 6 adapter wave-1 (Phase 3) · TOML normalize+backup+cảnh báo (Phase 4) · Secrets plaintext MVP + Keychain v1.1 (Phase 4).

#### Action Items
- [x] plan.md bỏ chữ "đề xuất" trước MIT; marker vào phase-04, phase-07
- [x] Phase 1 spike resolve 2 mục Unverified — symlink per-agent: verified (ma trận trong reports/spike-adapter-matrix.md); FoundationModels: unavailable trên máy dev (appleIntelligenceNotEnabled) → keyword fallback là đường chính Phase 5

#### Impact on Phases
- Phase 4, Phase 7: thiết kế giữ nguyên (đã đúng như quyết định) — chỉ thêm marker validation.

### Whole-Plan Consistency Sweep
Quét 8 file sau propagation: không còn "đề xuất MIT"; không adapter nào ngoài bộ 6 được tham chiếu; không mâu thuẫn plan.md ↔ phase files; "AgentOS" chỉ còn dưới dạng chú thích tên cũ (chủ đích). **Unresolved contradictions: 0.**

<!-- slug: ageos-mvp -->
