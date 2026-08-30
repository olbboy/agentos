# AgeOS MVP — Xác nhận độc lập test suite + CLI (tester, 2026-08-30 05:46)

Máy: macOS 26.5.2, Swift 6.3.3, Xcode 26.6. Không sửa code — chỉ verify.

## 1. `swift test` — PASS khớp kỳ vọng

```
swift test 2>&1 | tail -5
✔ Test run with 62 tests in 22 suites passed after 11.646 seconds.
```
- 62/62 tests, 22/22 suites, 0 failed, 0 error, 0 warning (grep log riêng để confirm).
- 1 test tên `httpTransportIsSkippedInMvp` — đây là test PASS bình thường (assert HTTP transport out-of-scope cho MVP), không phải test bị skip thật.
- 22 suite bao phủ rộng: AdapterRegistry, BudgetMeter, ConfigWriter (JSON+TOML golden), DedupeEngine, DescriptionLinter, Doctor drift, EffectiveLoadScanner, GitHubSource (mock HTTP), HealthCheck stdio, LinkEngine enable/disable/propagate, Lockfile schema, McpManager 3-client, McpRegistrySource, McpbImporter, QualityScorer, Scan performance (500 skills <30s), SkillParser golden, **Static-only guarantee** (booby-trap security test), Store versioning, SyncEngine, ageos-mcp loopback. Coverage tốt trên core.

## 2. `xcodebuild -only-testing:AgeOSTests` — BLOCKED (môi trường, không phải bug code)

Kỳ vọng: 3 unit test pass (`testRefreshOnEmptyHomeDoesNotCrash`, `testAddSourceToggleFlow`, `testErrorSurfacesToBanner` — đọc source `apps/AgeOS/Tests/AppModelTests.swift`, đúng 3 test).

**Kết quả thật: `** TEST FAILED **` — nhưng 0 test case nào thực sự chạy** (`grep -c "Test Case" log` = 0 cả 2 lần thử). Build + codesign OK, nhưng app test-host (`AgeOS[pid]`) hang khi launch, timeout sau 120s: `"Timed out after 120.0s while initiating control session with daemon"` → `"The test runner hung before establishing connection."`

Đã thử lại 2 lần (sandbox mặc định + `dangerouslyDisableSandbox: true`) — **fail giống hệt nhau** (~704.485s / 704.491s, cùng error signature) → loại trừ nguyên nhân do sandbox của Bash tool.

**Root cause xác nhận qua unified log** (`log show --predicate 'process == "tccd"'` trong đúng window hang):
```
[com.apple.TCC:access] AUTHREQ_CTX: ... service=kTCCServiceDeveloperTool, preflight=yes ...
[com.apple.TCC:access] Service kTCCServiceDeveloperTool does not allow prompting; returning denied.
```
→ TCC service `kTCCServiceDeveloperTool` bị denied cho process chain hiện tại, và service này **không cho phép hiện popup xin quyền** (khác Camera/Accessibility) — phải pre-grant thủ công qua System Settings → Privacy & Security → **Developer Tools** → bật cho app chịu trách nhiệm (Terminal/claude.app trong chain). Không có cách nào remedy từ Bash-only, và tôi không có quyền/tool GUI trong sub-agent này để tự bật.

Đã consult `kongming` để đối chiếu chẩn đoán độc lập (advisory, chạy song song) — kết luận dưới đây dựa trên bằng chứng log trực tiếp (không phụ thuộc kongming phản hồi kịp).

**Kết luận:** đây là **environment prerequisite chưa được set trên máy chạy sub-agent này**, không phải lỗi trong AgeOSTests hay code AgeOS. Task ghi chú "AgeOSUITests cần TCC interactive" — thực tế AgeOSTests (unit test, hosted trong AgeOS.app vì cần `@testable import AgeOS`) **cũng cần 1 TCC gate riêng** (Developer Tools, loại silent-deny chứ không phải loại prompt). Đáng note lại giả định ban đầu trong task brief.

**Không unblock được** trong phạm vi sub-agent này — cần user tự bật Developer Tools permission rồi chạy lại lệnh xcodebuild y hệt.

## 3. CLI smoke test (`AGEOS_HOME=/tmp/ageos-tester-home`) — PASS

| Lệnh | Kết quả | Exit |
|---|---|---|
| `targets list` | 6 adapter đúng: antigravity, claude-code, claude-desktop, codex, grok, universal-agents | 0 |
| `targets list --json` | JSON hợp lệ, đủ field `detected/verified/mcp/skills/preferredMode` | 0 |
| `list` | "Library trống. Bắt đầu: ageos source add …" | 0 |
| `doctor` | "✓ Không phát hiện vấn đề nào — lockfile khớp filesystem" | 0 |
| `budget` | Chạy xong không crash | 0 |
| `mcp list` | "Library MCP trống. Add: ageos mcp add …" | 0 |
| `source add <local dir 1 skill>` | "✓ Nguồn local/local-skill-src @ a8ae554243b4 — 1 skill" | 0 |
| `list` sau add | Đúng 1 skill, đúng id/description | 0 |

**Phát hiện quan trọng — `budget` đọc thẳng thư mục agent thật bất kể `AGEOS_HOME`:** output show real data (claude-code 136 skills/7 MCP, grok 169 skills, codex 20 skills, antigravity 9 skills…) — đúng thiết kế (effective-load map phải đọc máy thật để có ý nghĩa), `AGEOS_HOME` chỉ cô lập library/lockfile/index của chính AgeOS, không cô lập nơi `budget`/`adopt`/`scan` **đọc** từ. Đã verify **read-only** — so mtime `~/.claude/skills`, `~/.codex/skills`, `~/.grok/skills`, `~/.agents/skills` trước/sau: không đổi. Không ghi gì vào máy thật.

**Sai khác so với kịch bản đề bài — "enable --target <adapter KHÔNG detect>":** `targets list --json` cho thấy **cả 6 adapter đều `detected: true`** trên máy này (máy dev thật, đã cài đủ agent để verify — đúng README "Verified on real machine"). Không có adapter nào "chưa detect" để test an toàn theo đúng kịch bản gốc. Đọc source xác nhận thêm: `EnableCommand`/`LinkEngine.enableLocked` **không hề check `isDetected()`** — enable không gate theo detection status (chỉ check adapter id có tồn tại + có hỗ trợ skills). Vậy kịch bản "known-but-undetected target → lỗi" **không tồn tại như 1 code path riêng** trong implementation hiện tại — đây là quan sát về thiết kế, để dev xác nhận có chủ ý hay không, không phải bug.

→ Đã thay bằng 2 test âm tính an toàn (không đụng dir thật):
1. `enable local/local-skill-src/tester-smoke-skill --target does-not-exist-adapter` →
   ```
   ageos: Không có adapter 'does-not-exist-adapter'
     → Adapter khả dụng: antigravity, claude-code, claude-desktop, codex, grok, universal-agents. Thêm adapter mới bằng file JSON trong ~/.ageos/adapters/
   ```
   Exit 1, remedy rõ, **không stack trace**.
2. `enable totally-bogus-skill-xyz --target claude-code --project /tmp/.../fake-project` →
   ```
   ageos: Không tìm thấy skill 'totally-bogus-skill-xyz' trong index
     → Chạy `ageos list` xem skill khả dụng, hoặc `ageos sync` để cập nhật
   ```
   Exit 1, remedy rõ. `fake-project` không hề được tạo (fail trước mọi FS write) — xác nhận thêm zero-risk.

Đọc code xác nhận error path an toàn toàn diện: mọi lỗi trong `enable`/`disable` đi qua `AgeOSError` có `code+message+remedy` → `CLIRuntime.fail()` in stderr `"ageos: <msg>\n  → <remedy>"` rồi `exit(1)` (`Sources/AgeOSCLI/AgeosCommand.swift:26-35`, `Sources/AgeOSCore/adapters/AdapterRegistry.swift:53-60`, `Sources/AgeOSCLI/EnableCommand.swift:26-53`) — không có force-unwrap trên đường resolve adapter id.

Đã validate thêm: `targets list --json` và `list --json` parse được bằng `python3 json.load` (không chỉ "trông giống JSON") — cả 2 OK.

Đã cleanup: `rm -rf /tmp/ageos-tester-home /tmp/ageos-dd-tester` — exit 0, cả 2 dir không còn.

## 4. Exit codes

- Lệnh OK (targets/list/doctor/budget/mcp list/source add/list --json/`--version`): **exit 0** — đúng kỳ vọng.
- Lỗi app-level (unknown adapter, unknown skill — qua `AgeOSError`→`CLIRuntime.fail`): **exit 1** — đúng kỳ vọng.
- **Nuance:** lỗi ở tầng ArgumentParser (subcommand không tồn tại, vd `ageos totally-bogus-subcommand`) → **exit 64** (EX_USAGE chuẩn Swift ArgumentParser), không phải 1. Vẫn non-zero/fail đúng semantics, nhưng không đồng nhất tuyệt đối "fail luôn = 1" như đề bài giả định — đây là hành vi chuẩn/idiomatic của swift-argument-parser, không phải bug.

## 5. An toàn — không đụng thư mục agent thật

- Mọi lệnh CLI đều chạy với `AGEOS_HOME=/tmp/ageos-tester-home` set trong cùng lệnh (không dựa vào persisted shell state).
- Verify mtime `~/.claude.json`, `~/.codex/config.toml`, `~/.grok/config.toml`, `claude_desktop_config.json`, và 4 dir `skills` thật — **không đổi** trong suốt session test (trừ `~/.claude.json` đổi ở 05:58 nhưng đó là hoạt động bình thường của chính Claude Code session này, không phải do lệnh `ageos` nào gây ra — không có code path nào trong `budget`/`doctor`/`enable` (unknown-target case) từng mở file đó để ghi).
- Real `~/.ageos` (đã tồn tại từ trước, có backup từ 2026-08-29 tối) — mtime top-level đổi lúc 06:02 nhưng do 1 session/workflow khác (`plans/reports/cook-260830-0417-ageos-mvp.md` cũng vừa update cùng lúc) chạy song song trên cùng máy, **không phải do sub-agent tester này** (mọi lệnh của tôi đều export AGEOS_HOME riêng, và `list` sau `source add` chỉ show đúng 1 skill test — bằng chứng trực tiếp tôi luôn thao tác trên home tạm, không phải home thật).
- Không còn process orphan (`ps aux | grep -i ageos/xcodebuild/xctest` sau 2 lần xcodebuild hang — sạch).

## Vấn đề/concerns cần user chú ý

1. **xcodebuild AgeOSTests chưa verify được** (BLOCKED, không phải fail) — cần bật System Settings → Privacy & Security → **Developer Tools** cho app/terminal chịu trách nhiệm trong chain chạy xcodebuild, rồi chạy lại nguyên lệnh gốc để xác nhận 3 unit test thật sự pass.
2. Thiết kế `enable` không gate theo `isDetected()` — enable tới adapter id hợp lệ nhưng chưa cài trên máy vẫn proceed (tạo dir global path nếu chưa có) thay vì báo lỗi. Nên xác nhận đây là chủ ý (pre-provision cho agent chưa cài) hay cần thêm cảnh báo/confirm.
3. Exit code không đồng nhất tuyệt đối 1 cho mọi lỗi (64 cho lỗi cú pháp CLI) — hành vi chuẩn ArgumentParser, chỉ note để không bất ngờ khi viết script wrapper dựa vào exit code.

---
Status: DONE_WITH_CONCERNS
Summary: `swift test` xanh tuyệt đối (62/62, 22 suite, khớp kỳ vọng). CLI smoke test qua hết (6 adapter, empty-state, doctor sạch, budget không crash, enable error path sạch có remedy, exit code đúng, không đụng máy thật) — 1 kịch bản gốc (target chưa detect) phải thay thế vì máy dev đã cài đủ 6 adapter thật. `xcodebuild -only-testing:AgeOSTests` BLOCKED bởi TCC `kTCCServiceDeveloperTool` bị deny-silent trên máy — root cause đã xác nhận qua unified log, không phải lỗi code, cần user bật quyền Developer Tools thủ công rồi chạy lại.
Concerns/Blockers:
- xcodebuild AgeOSTests: chưa xác nhận được 3 unit test pass/fail thật sự — cần user grant Developer Tools TCC rồi re-run `cd apps/AgeOS && xcodebuild -project AgeOS.xcodeproj -scheme AgeOS -derivedDataPath <dd-path-mới> test -only-testing:AgeOSTests`.
- Nhờ xác nhận ý định thiết kế: `enable` có nên chặn khi target chưa `detected` không?
