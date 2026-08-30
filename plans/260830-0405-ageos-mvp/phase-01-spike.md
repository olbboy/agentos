---
phase: 1
title: "Phase 1: Spike & Adapter Verification"
status: done
priority: P1
effort: "1d"
dependencies: []
---

# Phase 1: Spike & Adapter Verification

## Overview
Xác minh thực nghiệm các giả định rủi ro nhất TRƯỚC khi viết code sản phẩm: hành vi symlink từng agent, path thật của Grok/Antigravity, handshake MCP swift-sdk, khả dụng FoundationModels. Kết quả đổ trực tiếp vào adapter JSON (Phase 3).

## Requirements
- Functional: ma trận capability per agent (folder-symlink / file-symlink / copy / project walk-up); Grok path chốt bằng `grok inspect`; hello MCP server Swift chạy trong Claude Code.
- Non-functional: chỉ tạo artefact test prefix `ageos-spike-*` trong thư mục agent, dọn sạch sau spike; code spike là throwaway, không merge vào core.

## Architecture
Script + mini-SPM trong `spike/` (ngoài code sản phẩm). Report tại `plans/260830-0405-ageos-mvp/reports/`.

## Related Code Files
- Create: `spike/spike-symlink-matrix.sh`, `spike/HelloMCP/` (SPM executable + swift-sdk), `plans/260830-0405-ageos-mvp/reports/spike-adapter-matrix.md`

## Implementation Steps
1. Tạo skill test `ageos-spike-hello` (SKILL.md chuẩn agentskills.io, description độc nhất để dò discovery).
2. Với từng agent có trên máy (claude, codex, grok, antigravity): thử folder-symlink → file-symlink → copy vào path global; xác nhận discovery headless (vd `claude -p`, `codex exec`, `grok -p`, kèm lệnh liệt kê skill của từng CLI); ghi ma trận. Lặp cho project scope (walk-up).
3. `grok inspect` trong project test → chốt `~/.grok/skills` vs `~/.agents/skills` (+ MCP `~/.grok/config.toml`).
4. Antigravity: phân xử `~/.gemini/skills` vs `~/.gemini/config/skills` (nguồn mâu thuẫn) + workspace `.agents/`, MCP `~/.gemini/config/mcp_config.json`.
5. HelloMCP: executable swift-sdk 1 tool `ping`; `claude mcp add` → tool call thành công; đo handshake + tokens schema (từ `/context`).
6. Check FoundationModels (`SystemLanguageModel.availability`) + NLContextualEmbedding load asset EN → ghi nhận fallback path.
7. Đo hệ số budget: bật 5 rồi 20 skill test trong Claude Code, so `/context` → hệ số token/char cho Budget Meter (Phase 5).
8. Viết `spike-adapter-matrix.md`, draft giá trị vào `adapters/*.json`, dọn artefact.

## Todo
- [x] Skill test + ma trận symlink 4 agent (global + project) — natural experiment + probe phân lập (codex qua `debug prompt-input`, grok qua `inspect --json`)
- [x] Chốt path Grok (`~/.grok/skills` + universal) + Antigravity (`~/.gemini/config/skills`, verified:false) bằng bằng chứng máy thật
- [x] HelloMCP: swift-sdk 0.12.1, handshake stdio + tools/call pass (427ms cold); E2E qua nested `claude -p` bị chặn OAuth headless — verify thủ công ghi trong report
- [x] FoundationModels: unavailable(appleIntelligenceNotEnabled) → keyword fallback là đường chính; NLCtxEmbedding OK dim=512 nhưng cosine gap hẹp → Phase 5 phải mean-center + calibrate; hệ số budget 4.0 bytes/token (khớp grok approxTokens)
- [x] Report `reports/spike-adapter-matrix.md` + 6 adapter JSON (`adapters/`) + cleanup (0 artefact còn lại)

## Success Criteria
- [x] Ma trận đủ 4 agent (antigravity `verified:false` — không có CLI headless)
- [x] HelloMCP tool call OK qua raw stdio (protocol 2025-06-18), schema ≈50 tokens; risk swift-sdk fail ĐÓNG
- [x] Không còn artefact `ageos-spike-*` trong thư mục agent (kiểm chứng bằng grep = 0)

## Risk Assessment
- Agent chưa cài trên máy → signal: command not found; response: giá trị từ docs + `verified:false`, doctor re-verify lúc runtime — không block.
- swift-sdk handshake fail → signal: initialize timeout/error; response: thử release cũ hơn, nếu vẫn fail → quyết định replan Phase 6 sang stdio JSON-RPC tự viết (nhỏ).
- Headless discovery không đo được ở agent nào đó → signal: CLI không có lệnh liệt kê skill; response: test thủ công 1 lần, ghi chú cách verify trong adapter notes.
