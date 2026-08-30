---
phase: 6
title: "Phase 6: Surfaces"
status: done
priority: P1
effort: "6d"
dependencies: [5]
---

# Phase 6: Surfaces

## Overview
Ba mặt điều khiển trên cùng core: MCP server `ageos-mcp` (agent tự phục vụ — dogfood qua chính Phase 4), CLI hoàn thiện, app SwiftUI + menu bar.

## Requirements
- Functional:
  - `ageos-mcp` (stdio, swift-sdk) tools: `search_skills`, `skill_info`, `install_skill`, `enable_skill`, `disable_skill`, `list_targets`, `scan_library`, `budget_report`, `doctor` — mô tả tool ngắn (chính mình cũng phải qua Budget Meter!).
  - App `AgeOS.app` (SwiftUI, macOS 26): Library browser (search/filter theo classification/quality), Target Matrix (skill × agent toggle, chọn scope), Budget dashboard, Scan results (dupe/deprecated/lint + hành động hợp nhất), Adopt wizard (onboarding "tìm thấy N skills / M app, K trùng"), MCP manager (enable/health/env form), Settings; MenuBarExtra: toggle nhanh + trạng thái sync.
  - FSEvents watch thư mục target → tự cập nhật trạng thái khi ngoài ý muốn (agent/user sửa tay) + gợi ý doctor.
  - CLI: `--json` phủ hết lệnh, shell completion, exit codes nhất quán.
- Non-functional: app không chạy daemon nền ngoài FSEvents của chính nó; thao tác nguy hiểm (disable hàng loạt, force copy) có confirm; theo macOS HIG; VoiceOver labels cho controls chính.

## Architecture
- `AgeOS.xcodeproj` (app target) tham chiếu local SPM package; ViewModels observable gọi thẳng `AgeOSCore` (không IPC).
- `Sources/AgeOSMCPServer/` executable dùng swift-sdk; đăng ký vào agents bằng chính ConfigWriter Phase 4 (`ageos mcp enable ageos`).
- UI theo HIG, tối giản; nếu cần design pass sâu → dùng skill frontend-design/ui-ux ở lúc cook, không chế thêm design system riêng.

## Related Code Files
- Create: `Sources/AgeOSMCPServer/**`, `apps/AgeOS/**` (Xcode project, Views/ ViewModels/ PascalCase), completions script, `Tests/AgeOSMCPServerTests/**`, ViewModel tests
- Modify: CLI (completions, exit codes), `AgeOSCore` (API surface cho ViewModel nếu thiếu)

## Implementation Steps
1. `ageos-mcp`: khung server + 9 tools mapping vào core API; schema gọn; integration test bằng MCP client swift-sdk (loopback).
2. Dogfood: `ageos mcp enable ageos --target claude-code` → từ Claude Code gọi `search_skills`→`install_skill`→`enable_skill` end-to-end.
3. App skeleton + navigation + DI core.
4. Library browser + Target Matrix (bảng toggle là màn hình đinh).
5. Budget dashboard + Scan results (hành động: hợp nhất dupe, disable deprecated).
6. Adopt wizard (chạy EffectiveLoadScanner, chọn import).
7. MCP manager view (env form, health badge).
8. MenuBarExtra + FSEvents watcher.
9. CLI completions + exit-code sweep; ViewModel unit tests + 1 UI smoke test.

## Todo
- [x] ageos-mcp 9 tools (swift-sdk 0.12.1) + loopback E2E test: initialize → tools/list → install→search→enable→doctor→budget→disable, description mỗi tool <120 chars (test enforce), schema tổng ≈458 tokens
- [x] Dogfood: `ageos mcp add --manual ageos` + `enable --target claude-code` bằng CHÍNH ageos → entry trong ~/.claude.json thật (có backup), health 9 tools/569ms; gọi tool từ session Claude Code MỚI là bước user verify (nested claude -p bị chặn OAuth — xem spike report)
- [x] App: Library browser (search/filter/add-source) + Target Matrix (Table skill × adapter, toggle switch, màn đinh)
- [x] Budget dashboard (progress vs ngưỡng, top skills, warnings) + Scan view (dupe/deprecated/lint + doctor, confirm trước --fix)
- [x] Adopt wizard (stats + duplicated paths per agent + import 1 nút có confirm)
- [x] MCP manager view (health badge, sensitive env warning, toggle per client)
- [x] MenuBarExtra (managed count, sync gần nhất, sync/doctor nhanh) + FSEvents watcher (latency 1s, gợi ý doctor khi thư mục agent bị sửa ngoài)
- [x] CLI: completions script (zsh/bash/fish qua ArgumentParser), exit codes nhất quán (0 ok / 1 lỗi+health-fail / 64 usage); app unit tests 3/3 (bắt được bug refreshAll xóa mất error banner)

## Success Criteria
- [x] Acceptance #6: flow search_skills→install_skill→enable_skill pass qua loopback E2E (đúng protocol Claude Code dùng); bước cuối "từ Claude Code thật" đã dogfood-register, user verify ở session mới
- [x] Parity 3 mặt: mọi thao tác GUI (source add/sync, enable/disable, scan, budget, adopt, mcp, doctor) đều có CLI `--json` + tool MCP tương đương
- [x] FSEvents → refreshAll → lock/inventory cập nhật + gợi ý doctor (toggle đọc từ lockfile — nguồn chân lý)
- [x] App native thuần Swift/SwiftUI — zero Node/Docker/runtime ngoài; UI smoke test viết xong nhưng chạy cần user approve Automation permission lần đầu (TCC — ghi trong CONTRIBUTING + deployment guide)

## Risk Assessment
- swift-sdk thiếu tính năng server cần (đã spike ping ở Phase 1) → signal: không expose được tool schema như ý; response: fallback stdio JSON-RPC tự viết cho đúng 9 tools (bounded).
- Phạm vi UI phình (nhiều màn) → signal: quá 6 ngày; response: cắt theo thứ tự giữ Target Matrix + Adopt + Budget (3 màn đinh), phần còn lại dồn v0.2 — KHÔNG cắt parity CLI/MCP.
- FSEvents bắn dồn dập khi sync lớn → signal: CPU cao/UI giật; response: debounce + coalesce events.
