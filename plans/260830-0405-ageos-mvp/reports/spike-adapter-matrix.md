# Spike Report — Adapter Matrix (Phase 1)

Date: 2026-08-30 · Máy: macOS 26.5.2 / Swift 6.3.3 / Xcode 26.6 · Reproduce: `spike/spike-symlink-matrix.sh`

## Ma trận capability (bằng chứng máy thật)

| Agent | Global skills path | Project path | Folder-symlink | File-symlink | Verified | Nguồn bằng chứng |
|---|---|---|---|---|---|---|
| claude-code | `~/.claude/skills` (+ plugin cache) | `.claude/skills` | ✅ abs+rel | chưa đo (không cần) | ✅ | 22 symlink đang load trong chính session Claude Code hiện hành (natural experiment) |
| codex 0.150.1 | `~/.codex/skills` + `~/.agents/skills` | `.agents/skills` ✅ | ✅ | ❌ KHÔNG nhận | ✅ | `codex debug prompt-input` (render prompt, miễn phí): probe phân lập trong `~/.codex/skills` DISCOVERED; file-symlink probe không xuất hiện (khớp issue #8369) |
| grok 1.0.13 | `~/.grok/skills` + `~/.agents/skills` + compat `~/.claude/skills` + `~/.grok/bundled/skills` + Claude plugin cache | `.agents/skills` ✅ | ✅ | ✅ | ✅ | `grok inspect --json`: 230 skills, source path per skill |
| antigravity | `~/.gemini/config/skills` (KHÔNG phải `~/.gemini/skills` — dir đó là gemini-cli legacy Jun/8) | `.agents/` (docs) | symlink tồn tại do tool khác cài chủ đích (7/8) | — | ❌ `verified:false` | FS evidence; không có CLI headless để verify discovery; doctor re-verify runtime |
| claude-desktop | (mcp-only) | — | — | — | ✅ | `~/Library/Application Support/Claude/claude_desktop_config.json` tồn tại, `mcpServers` có entry thật |
| universal (`~/.agents/skills`) | đọc bởi codex ✅ + grok ✅ | `.agents/skills` | ✅ | — | ✅ | higgsfield-* chỉ nằm ở đây vẫn xuất hiện trong prompt codex; goose-* resolved từ đây trong grok inspect |

### Precedence dedup (đo từ grok inspect)
`~/.grok/skills` > `~/.agents/skills` > `~/.claude/skills` (higgsfield-* trùng 2 nơi → grok chọn `.grok`; goose-* trùng `.agents`+`.claude` → chọn `.agents`). Grok đọc cả MCP từ `~/.claude.json` (`vendor: claude, compatibilityStatus: enabled`) và plugin Claude → **một skill có thể bị load 3+ lần trong 1 agent** — đầu vào trực tiếp cho EffectiveLoadScanner (Phase 5).

### Codex catalog: description bị cắt ~160 chars trong prompt (`skill-installer` đứt giữa câu). BudgetMeter cost codex = name + min(desc,160).

## MCP config per client (verified trên máy)

| Client | Path | Format | Key |
|---|---|---|---|
| claude-code | `~/.claude.json` (global) + `<proj>/.mcp.json` | JSON | `mcpServers` |
| claude-desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` | JSON | `mcpServers` |
| codex | `~/.codex/config.toml` | TOML | `[mcp_servers.<name>]` |
| grok | `~/.grok/config.toml` | TOML | `[mcp_servers.<name>]` (docs bundled `07-mcp-servers.md`; hỗ trợ `command/args/env/enabled/startup_timeout_sec`, HTTP `url`) |
| antigravity | `~/.gemini/config/mcp_config.json` | JSON | `mcpServers` (file tồn tại, schema khớp) |

Ghi chú Phase 4: cả `codex mcp add` và `grok mcp add` đều tồn tại → hướng delegate-qua-CLI là upgrade an toàn khả dĩ cho v1.1 (tránh hẳn rủi ro TOML normalize). MVP giữ quyết định đã validate: TomlConfigWriter normalize + backup + cảnh báo.

## HelloMCP (swift-sdk)

- **swift-sdk 0.12.1** resolve + build sạch lần đầu (SPM, macOS 13+ target OK).
- Handshake stdio (client JSON-RPC tự viết): initialize 427ms cold-start → `notifications/initialized` → `tools/list` → `tools/call ping` trả `pong zx7q`. Protocol `2025-06-18`. Schema 1 tool ≈ 200 chars ≈ 50 tokens.
- API note Phase 6: `.text(_:metadata:)` deprecated → dùng `.text(text:annotations:_meta:)`; server pattern: `Server(name:version:capabilities:)` + `withMethodHandler(ListTools/CallTool)` + `StdioTransport` + `waitUntilCompleted()`.
- E2E qua `claude -p --mcp-config`: **bị chặn** — nested claude CLI báo `OAuth session expired and could not be refreshed` (giới hạn môi trường headless, không phải lỗi server). Verify thủ công khi cần: `claude mcp add hello <bin>` → `/mcp` → gọi tool. Raw-protocol pass đủ tin cậy cho quyết định dùng swift-sdk (risk swift-sdk fail → ĐÓNG, không cần fallback JSON-RPC tự viết).

## FoundationModels + NLContextualEmbedding

- `SystemLanguageModel.availability` = **unavailable(appleIntelligenceNotEnabled)** trên máy dev → fallback keyword classifier là ĐƯỜNG CHÍNH thực tế (Phase 5 phải test kỹ nhánh này; FM là enhancement khi user bật Apple Intelligence). Resolve mục Unverified #2 của Validation Session 1.
- NLContextualEmbedding EN: init OK, dim=512, assets sẵn, embed chạy. **CẢNH BÁO**: cosine mean-pooling gap hẹp — cặp tương tự 0.951 vs cặp KHÁC nghĩa 0.904 → ngưỡng 0.90 của plan KHÔNG dùng được trên raw vectors. Phase 5 phải: mean-center vectors trên corpus + calibrate ngưỡng trên fixtures (dải khả thi ~0.93-0.96 sau centering), đúng risk response có sẵn trong plan (fallback model2vec.swift nếu vẫn kém).

## Hệ số Budget Meter

- Đo trực tiếp `/context` qua nested `claude -p` bất khả thi (OAuth như trên). Dùng hệ số **4.0 bytes/token** — khớp chính xác cách grok tự ước (`grok inspect` trả `sizeBytes`/`approxTokens` = 4.00 trên mọi file đo). Sai số chấp nhận ±20% (đã chốt trong plan). Verify thủ công: bật/tắt N skill → so `/context` trong Claude Code interactive.

## Kết luận đổ vào adapter JSON

1. 6 adapter bundled: claude-code, codex, universal-agents, grok, antigravity (`verified:false` cho skills discovery), claude-desktop (mcp-only). Giá trị trong `adapters/*.json` (repo root).
2. Codex: `preferredMode=copy` GIỮ NGUYÊN quyết định validate (folder-symlink đã verified hoạt động 30/8 — ghi note trong adapter; flip sang symlink là data update sau khi theo dõi #8369, không cần release).
3. Grok: primary `~/.grok/skills` (đúng advisory); universal adapter cover thêm `~/.agents/skills` cho cả codex+grok.
4. Antigravity: skills `~/.gemini/config/skills`, MCP `~/.gemini/config/mcp_config.json`.

## Cleanup

- `~/.codex/skills`: 0 artefact `ageos-spike-*` còn lại (probe tạo + xóa trong cùng lệnh). Không đụng thư mục agent nào khác — claude/grok/antigravity verify bằng natural experiment (symlink có sẵn của user) + render-prompt/read-only inspect.
- Scratch project spike (scratchpad session) đã xóa; `spike/` giữ HelloMCP + fm-check.swift + script này làm tài liệu tái lập (throwaway, không merge vào core).

## Unresolved

- Antigravity discovery runtime (không CLI) → `verified:false`, doctor re-verify khi user thật chạy.
- Hành vi walk-up của codex/grok từ SUBDIR sâu (đo từ project root OK; subdir chưa đo — ít rủi ro, LinkEngine link tại root).
