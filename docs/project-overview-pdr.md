# AgeOS — Project Overview / PDR

## Problem
Skills + MCP servers phân mảnh across agents (claude-code, codex, grok, antigravity, claude-desktop). Đo thực tế máy dev 30/8/2026: 169 skill distinct, 345 load entries, 147 skill nằm ≥2 agent, 18 cặp exact-dupe, claude-code gánh ≈10k tokens catalog luôn-tải. Không tool nào quản tập trung + đo chi phí context.

## Product
Native macOS manager (Swift 6, macOS 26+): 1 library trung tâm `~/.ageos/` + adapter data-driven phân phối per-agent + intelligence (dupe/deprecated/quality/budget) + 3 surfaces (SwiftUI app, CLI `ageos`, MCP server `ageos-mcp`).

## Users
Dev dùng ≥2 coding agent trên macOS; power users quản skills như dependencies.

## Differentiators
1. Effective-load map — phơi hiện trạng thật (kể cả compat paths, plugin cache).
2. Context Budget Meter per agent (±20%).
3. Adapter = JSON → cộng đồng thêm agent không cần release.
4. Safety invariants: không đụng đồ user, config parse-merge + backup, static-only scan.

## Decisions (chốt tại plan validate 30/8/2026)
- OSS MIT · tên AgeOS (repo dir giữ `agentos`) · macOS 26+ (FoundationModels optional, keyword fallback là đường chính).
- 6 adapter wave-1: claude-code, codex, grok, antigravity, claude-desktop, universal-agents.
- TOML write: TOMLKit normalize + cảnh báo + backup (line-targeted editor = replan trigger nếu cộng đồng phản ứng).
- Secrets MCP plaintext MVP, đánh dấu `sensitive`; Keychain = v1.1.
- Codex preferredMode=copy (folder-symlink verified hoạt động 30/8 — flip là data update sau khi theo dõi openai/codex#8369).

## Status
MVP code-complete (Phases 1–6), release lane chuẩn bị xong (Phase 7) — publish chờ quyết định user (repo public, tap, Developer ID). Chi tiết: `plans/260830-0405-ageos-mvp/`.

## Roadmap sau v0.1.0
Keychain secrets (v1.1) · FM classification refine · line-targeted TOML nếu cần · thêm adapter cộng đồng · Sparkle update (cần Developer ID).
