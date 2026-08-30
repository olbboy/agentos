---
phase: 4
title: "Phase 4: MCP Distribution"
status: done
priority: P1
effort: "4d"
dependencies: [1, 2]
---

# Phase 4: MCP Distribution

## Overview
Quản lý MCP servers: nguồn (official registry, .mcpb, manual), ghi config an toàn vào từng client (JSON/TOML, parse-merge + backup + atomic), health-check handshake — dữ liệu schema-tokens từ health nuôi Budget Meter (Phase 5).

## Requirements
- Functional: `ageos mcp add|search|enable|disable|health`; nguồn: registry.modelcontextprotocol.io API (server.json), import file `.mcpb` (unzip + manifest.json), thêm tay; targets: claude-code (`~/.claude.json` + project `.mcp.json`), claude-desktop (`claude_desktop_config.json`), codex + grok (`config.toml`), antigravity (`mcp_config.json`).
- Non-functional: KHÔNG BAO GIỜ regenerate cả file config — chỉ parse-merge entry của mình; backup vào `~/.ageos/backups/<ts>/` trước mọi lần ghi; atomic write; revert được (`ageos mcp restore-backup`); env nhạy cảm đánh dấu `sensitive` trong lockfile (Keychain là milestone v1.1, ghi chú không làm ở MVP).

<!-- Updated: Validation Session 1 - chốt TOML normalize+cảnh báo và secrets plaintext MVP (Keychain v1.1) -->

## Architecture
- `McpServerModel` từ server.json/manifest.mcpb (name namespace kiểu `io.github.owner/name`, command, args, env schema).
- `ConfigWriter` protocol → `JsonConfigWriter` (giữ key lạ, key order ổn định) + `TomlConfigWriter` (TOMLKit; chấp nhận normalize format — ghi rõ hạn chế: comment TOML của user có thể mất → mặc định chỉ sửa khối `mcp_servers.<name>`, cảnh báo trước lần ghi TOML đầu).
- HealthCheck: spawn stdio command → initialize → tools/list → đo latency + đếm tokens schema (hệ số Phase 1); timeout + kill sạch (không để process mồ côi — tuân process-management rules).
- Env flow MVP: enable hỏi giá trị env còn thiếu (CLI prompt / GUI form ở Phase 6), ghi theo format client yêu cầu.

## Related Code Files
- Create: `Sources/AgeOSCore/mcp/**` (McpServerModel, RegistrySource, McpbImporter, HealthCheck), `Sources/AgeOSCore/config-writers/**`, CLI subcommands, `Tests/**` (golden merge tests từng format)
- Modify: `adapters/*.json` (khối mcp), `Lockfile`, `Index`

## Implementation Steps
1. RegistrySource: search/get theo API registry chính thức; cache offline.
2. McpbImporter: unzip, validate manifest, copy payload vào `library/mcp/<ns>/<name>/<version>/`.
3. JsonConfigWriter: load → merge entry → backup → atomic write; golden tests: file có key lạ, entry user tự viết, JSON lỗi (→ dừng + báo, không sửa).
4. TomlConfigWriter tương tự cho codex/grok; test comment-loss được document.
5. HealthCheck stdio + báo cáo (ok/fail, latency, tool count, schema tokens); ghi vào Index.
6. CLI mcp add/search/enable/disable/health/restore-backup + `--json`.
7. E2E fake-home: enable cùng 1 server cho 3 client → format đúng từng client; disable gỡ đúng entry của mình.

## Todo
- [x] RegistrySource (API v0, decode khoan dung wrapped+flat, cache offline) — search thật ra io.github.upstash/context7
- [x] .mcpb import (ditto unzip, manifest validate, ${__dirname} resolve vào library/mcp)
- [x] JsonConfigWriter + golden tests (key lạ + entry user nguyên vẹn, refuse JSON hỏng không đụng file)
- [x] TomlConfigWriter + golden tests (TOMLKit normalize — có thể đổi kiểu quote/mất comment, cảnh báo trước ghi, backup luôn)
- [x] HealthCheck stdio: SIGTERM→2s→SIGKILL, test pgrep chứng minh 0 process mồ côi kể cả server treo
- [x] CLI mcp add/search/list/enable/disable/health/restore-backup + --json + --env KEY=VALUE
- [x] E2E 3-client fake-home + phát hiện & sửa bug backup đè nhau trong cùng giây (stamp mili-giây + suffix)

## Success Criteria
- [x] Enable server test (HelloMCP spike) cho claude-code + claude-desktop + grok THẬT: entry đúng format từng app, entry user nguyên vẹn, backup mili-giây; disable xong diff với backup GIỐNG HỆT (verified máy thật 30/8)
- [x] Config JSON hỏng sẵn → từ chối ghi + chỉ vị trí lỗi, file không bị đụng (golden test)
- [x] `ageos mcp health` pass server thật (initialize 22ms, 1 tool, schema ≈47 tokens), fail rõ với command sai; pgrep xác nhận 0 mồ côi kể cả server treo
- [x] Restore-backup phục hồi đúng (unit + diff thật)

## Risk Assessment
- Client đổi schema config (vd Claude Code đổi vị trí mcpServers) → signal: golden test fail sau khi client update / doctor báo entry không được client nhận; response: sửa adapter mcp block + writer nhỏ, có version detect.
- TOMLKit làm mất comment user → signal: diff sau ghi; response: đã document + cảnh báo trước; nếu phản ứng cộng đồng lớn → replan sang line-targeted edit.
- Server health spawn treo → signal: quá timeout; response: SIGTERM → SIGKILL, báo lỗi kèm stderr đuôi.
