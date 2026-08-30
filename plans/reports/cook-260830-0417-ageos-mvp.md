# Cook Report — AgeOS MVP (7 phases, 1 session)

Date: 2026-08-30 04:17→06:15 · Mode: code (plan path) · Plan: `plans/260830-0405-ageos-mvp/`

## Kết quả

| Phase | Status | Bằng chứng chính |
|---|---|---|
| 1 Spike | ✅ | Ma trận symlink 4 agent verified máy thật (0 chi phí quota: natural experiment + `codex debug prompt-input` + `grok inspect --json`); HelloMCP swift-sdk 0.12.1 handshake 427ms; FM unavailable → keyword fallback là đường chính; NLCtxEmbedding cosine gap hẹp → PHẢI mean-center. Report: `reports/spike-adapter-matrix.md` |
| 2 Core Engine | ✅ | SPM scaffold; parser/validator golden; Store version+swap atomic; GitHubSource ETag/sha; Lockfile v1; Index GRDB reindex. Smoke thật: anthropics/skills 20 skill, sync no-op lần 2, reindex khôi phục |
| 3 Skills Distribution | ✅ | 6 adapter JSON từ spike; LinkEngine symlink/copy+manifest+marker; doctor --fix; verified máy thật: enable claude-code (hot-load NGAY trong session Claude Code đang chạy) + codex copy; disable sạch |
| 4 MCP Distribution | ✅ | Registry chính thức + .mcpb + manual; Json/Toml writer parse-merge + backup ms; HealthCheck 0-orphan; verified thật 3 client (claude-code/desktop/grok) round-trip diff GIỐNG HỆT backup |
| 5 Intelligence | ✅ | Máy thật: 169 skill/345 entries/147 multi-agent, 18 exact + 16 near dupe, budget claude-code ≈9,992 tokens; scan 500 skills 11.3s; booby-trap test chứng minh static-only |
| 6 Surfaces | ✅ | ageos-mcp 9 tools (schema ≈458 tokens) loopback E2E; dogfood registered vào ~/.claude.json thật; SwiftUI app (6 view + MenuBar + FSEvents) build xanh + 3 unit tests; completions |
| 7 OSS Release | 🟡 local-ready | LICENSE MIT, README/CONTRIBUTING/SECURITY, docs/ ×4, CI+release workflows, release-lane.sh, cask template. Deps 100% permissive. **Publish chờ user** |

Tests: core 68/68 (23 suites, ~12s — gồm 6 regression test từ code review) + app unit 3/3. UI smoke viết xong — chạy cần user approve Automation (TCC) lần đầu.

## Bug thật bị bắt trong quá trình (đã sửa + có test chặn)
1. Store.listInstalled + Doctor orphan-scan: so path thô dính bẫy `/var`→`/private/var` — orphan-scan suýt XÓA NHẦM file hợp lệ khi `--fix`. Fix: `canonicalPath` tập trung.
2. ConfigBackup đè backup cùng-giây → restore sai bản. Fix: stamp mili-giây + suffix chống trùng.
3. AppModel: refreshAll() sau addSource lỗi xóa mất error banner. Fix: refresh chỉ khi không lỗi.
4. Validator quá nghiêm: description >1024 hạ error→warning (anthropics/skills/claude-api = 1068 chars mà Claude Code vẫn load).
5. JSONEncoder escape `/` làm output MCP khó đọc → `.withoutEscapingSlashes`.

## Quyết định giữ nguyên theo validate (không lật)
- Codex `preferredMode=copy` dù spike chứng minh folder-symlink hoạt động — ghi note trong adapter, flip là data update sau khi theo dõi openai/codex#8369.
- TOML normalize + cảnh báo (không line-targeted editor); phát hiện thêm hướng delegate `codex/grok mcp add` cho v1.1 (ghi spike report).

## Code review (code-reviewer subagent) + fix

Reviewer độc lập tìm: **1 Critical + 1 High + 2 Medium + 3 Low**. Đã fix cả 4 mục đầu NGAY trong session + 6 regression test (68/68 xanh, binary ~/.ageos/bin đã thay bản fix):

1. **Critical — LinkEngine.isOurs hằng-đúng**: disable() so path lockfile với chính nó → user thay symlink bằng dir riêng sẽ bị XÓA. Fix: isOurs chỉ tin bằng chứng vật lý (xattr marker / manifest / symlink-trỏ-vào-store), áp cho cả enable-preflight; vá thêm biến thể ở propagateVersionChange (đích mất manifest → skip + warn).
2. **High — race lockfile 2 tiến trình** (CLI + ageos-mcp song song là use-case chủ đích): RMW mất update → doctor --fix xóa nhầm dây chuyền. Fix: flock(2) qua LockfileMutex bọc 5 hàm mutate.
3. **Medium — HealthCheck tốn trọn timeout khi server chết sớm**: Fix markEOF qua readabilityHandler → fail nhanh (<5s, test /usr/bin/false).
4. **Medium — near-dupe phantom test trên CI thiếu assets**: Fix precomputedVectors tiêm được → test cơ chế centering+threshold deterministic.

Low (ghi nhận v1.1, không sửa MVP): adapter registry all-or-nothing khi 1 JSON hỏng (đã có CI test chặn PR); tarball extraction dựa bsdtar chống zip-slip (thêm containment check v1.1); Lockfile.load chưa validate schemaVersion; Index.rebuild N+1 transaction.

## Tester độc lập (tester subagent)

Báo cáo đầy đủ: `plans/reports/tester-260830-0546-mvp-verification.md`. Kết quả:
- `swift test` xác nhận độc lập PASS tuyệt đối (chạy trên snapshot trước fix review: 62/62; bản sau fix là 68/68 do orchestrator chạy).
- CLI smoke (AGEOS_HOME cô lập): 6 adapter đúng, empty-state + remedy đúng, error path sạch không stack trace, exit codes 0/1/64 (64 = usage, chuẩn ArgumentParser). Verify mtime: KHÔNG đụng thư mục agent thật.
- `xcodebuild AgeOSTests` từ context subagent bị TCC chặn (kTCCServiceDeveloperTool silent-deny) — không phải lỗi code; orchestrator đã chạy pass 3/3 từ context có quyền. User muốn tự chạy: bật System Settings → Privacy & Security → Developer Tools cho terminal.
- Câu hỏi thiết kế từ tester: `enable` không gate theo `isDetected()` — CHỦ Ý (enable trước khi cài agent là hợp lệ, agent cài sau tự nhận skill; doctor re-verify). Ghi nhận v1.1: in thêm warning khi target chưa detect.

## Blocked / cần user
1. **Publish v0.1.0**: chốt GitHub owner + bundle id, push repo public (secret-scan trước), tap cask, tag. Checklist: `docs/deployment-guide.md`.
2. ~~Gọi ageos-mcp từ session Claude Code thật~~ — **ĐÃ XONG 30/8 07:52**: server dogfood tự load vào session, `list_targets` + `budget_report` trả đúng qua đường MCP thật. Còn lại 1 verify thủ công: đối chiếu `ageos budget` vs `/context`.
3. **TCC bootstrap cho xcodebuild test** (1 lần, persistent): bật Developer Tools cho **/Applications/Claude.app** (xác nhận qua ancestry-walk; agent chẩn đoán độc lập corroborate root cause kTCCServiceDeveloperTool silent-deny) — pane: `open "x-apple.systempreferences:com.apple.preference.security?Privacy_DeveloperTool"`; sau đó AgeOSUITests sẽ hỏi thêm Automation (gate thứ 2, approve interactive).
4. **Commit**: repo đã `git init`, 0 commit — chờ user gật (đề xuất conventional commits theo phase hoặc 1 commit `feat: AgeOS MVP`).

## Trạng thái máy sau session
- `~/.ageos/` tồn tại (product home): library anthropics/skills@3b3fad9, bin/ (ageos, ageos-mcp release), backups các lần ghi config.
- `~/.claude.json` có entry `ageos` (dogfood, có backup, gỡ được: `ageos mcp disable ageos --target claude-code`).
- Mọi artefact spike/test đã dọn; thư mục agent khác nguyên trạng.
