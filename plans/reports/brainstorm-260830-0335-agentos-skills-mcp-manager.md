# Brainstorm — AgentOS: macOS hub quản lý & phân phối Skills + MCP servers

- Date: 2026-08-30 03:35 (+07)
- Type: brainstorm (contract + so sánh phương án + tư vấn tính năng)
- Status: đề xuất, chờ user chốt để chuyển `ak:plan`
- Repo: trống (greenfield), chưa có README/docs/plans

## Tóm tắt

Xây app macOS native ("AgentOS") = 1 Library trung tâm + adapter cho từng agent + 3 mặt điều khiển (GUI SwiftUI, CLI, MCP server stdio chạy native). Kéo skills/MCP từ nhiều nguồn về local, phân phối bằng symlink (copy-fallback khi agent không follow symlink), quét trùng lặp/deprecated/chất lượng. Khuyến nghị: all-Swift native (Phương án A). Khoảng trống thị trường: app hiện có chỉ quản lý MCP (MyMCP, MCP One, Fleur, MCP Orchestrator) hoặc chỉ skills qua CLI (vercel `npx skills`); chưa ai gộp skills + MCP + library intelligence trong 1 app native.

## Hợp đồng brainstorm

### Outcome
App macOS native gồm 3 mặt trên 1 core engine:
1. **Library trung tâm** `~/.agentos/` — pull skills (chuẩn SKILL.md/agentskills.io) + định nghĩa MCP server (server.json) từ nhiều nguồn: GitHub repo, official MCP Registry (registry.modelcontextprotocol.io), hệ sinh thái skills.sh, private git, HTTP. Version hóa, content-addressed, offline sau sync.
2. **Phân phối qua adapter** — mỗi agent 1 adapter khai báo: đường dẫn skills (global/project), cơ chế link (symlink|copy), format + vị trí MCP config, cách ghi an toàn. Target đợt đầu: Claude Code, Codex, Grok, Antigravity, Claude Desktop (+ Cursor/Gemini CLI dễ thêm).
3. **Library intelligence** — quét exact-dupe (hash), near-dupe (embedding on-device), deprecated (upstream archived/marker), quality score + phân loại taxonomy; tích hợp security scanner ngoài (cisco skill-scanner / snyk agent-scan).
4. **MCP server của chính app** (stdio, native binary, không Docker/Node) — agent tự `search/install/enable/scan` qua tool call.

### Constraints
- macOS 15+ (tính năng AI on-device degrade gracefully), universal binary, không root.
- Chỉ ghi vào: `~/.agentos` + thư mục/config đã tài liệu hóa của từng agent; mọi ghi config ngoài: parse-merge (không regenerate), backup, atomic write, revert được.
- Không bao giờ execute code fetch về trong lúc sync/scan (static analysis only) — skills là code chạy được, supply-chain risk thật (Snyk 2/2026: 36,8% skills công khai có flaw, 13,4% critical).
- Filesystem là source of truth; SQLite chỉ là index/cache rebuild được.
- Tuân chuẩn mở: agentskills.io (SKILL.md), MCP server.json; không phát minh format riêng.
- Phân phối ngoài Mac App Store (Developer ID + notarize) — sandbox MAS chặn ghi dotfolder của agent khác.

### Non-goals (MVP)
- Không host registry/cloud công khai riêng (pull-only client; team-share qua private git).
- Không phải skill-authoring IDE (chỉ "reveal in Finder / open in editor").
- Không supervise/proxy MCP process dài hạn (không phải gateway kiểu MCPBundler); chỉ health-check handshake.
- Không Windows/Linux/iOS; không marketplace/payments.
- Không tự viết security scanner sâu — tích hợp tool có sẵn, tự làm phần dedupe/rating (chưa ai làm).

### Acceptance criteria (MVP, kiểm chứng được)
1. `source add <github-url|registry>` → sync ≤60s, skills/MCP hiện trong GUI+CLI kèm metadata.
2. Enable skill scope global cho Claude Code → symlink `~/.claude/skills/<x>` → session mới dùng được skill; scope project → `.claude/skills/<x>`.
3. Enable cùng skill cho Codex (`~/.agents/skills`) ở chế độ copy-fallback → Codex nhận skill (Codex từng không follow symlink — issue openai/codex#8369).
4. Enable 1 MCP server cho Claude Code + Claude Desktop + Grok → entry đúng format từng app (JSON/TOML), có backup file trước khi ghi; `doctor` handshake pass.
5. Scan library có dupe cài sẵn: bắt exact-dupe, near-dupe (similarity ≥ ngưỡng), repo archived → flag deprecated ở lần sync kế.
6. MCP server của app: từ Claude Code gọi `search_skills` → `install_skill` → `enable_skill` end-to-end thành công.
7. Disable/remove: gỡ symlink/entry sạch, không đụng file user tự tạo; mọi op idempotent; uninstall app không làm hỏng agent.

## Ma trận target (bằng chứng 8/2026)

| Agent | Skills global | Skills project | Symlink? | MCP config |
|---|---|---|---|---|
| Claude Code | `~/.claude/skills/` | `.claude/skills/` | Follow (bug hiển thị `/skills` #14836) | `claude mcp` / `~/.claude.json`, project `.mcp.json` |
| Codex | `~/.agents/skills` (`~/.codex/skills` cũ) | `.agents/skills` (scan CWD→root) | Từng không (issue #8369) → copy-fallback | `~/.codex/config.toml` |
| Grok | `~/.grok/skills/` (chuẩn agentskills.io) | `.grok/` walk-up | cần verify | `~/.grok/config.toml` (merge cả `~/.claude.json`, `.cursor/mcp.json`, `.mcp.json`) |
| Antigravity | `~/.gemini/skills` (shared), `~/.gemini/antigravity-cli/skills` | `.agents/` workspace | cần verify | global `~/.gemini/config/mcp_config.json`, workspace `.agents/mcp_config.json` |
| Claude Desktop | — | — | — | `~/Library/Application Support/Claude/claude_desktop_config.json` |

→ Adapter phải là **data-driven** (file khai báo, không hardcode), có field `linkMode: symlink|copy`, `scopes`, `mcpWriter`. Phase implement: verify từng adapter bằng /deep-research + test thật (user đã cho phép trigger /essential-questions, deep-research).

## Phương án

### A — All-Swift native (khuyến nghị)
SwiftUI app (menu bar + main window) + core engine Swift + binary `agentos` (CLI + MCP stdio qua official modelcontextprotocol/swift-sdk, spec 2025-11-25, stdio ổn định). Fetch nguồn qua GitHub tarball API/HTTPS (không bắt buộc git), embedding near-dupe qua NLEmbedding/Foundation Models on-device. Interop hệ sinh thái ở tầng **data/protocol** (đọc index skills.sh, MCP Registry API, git/tarball) — không wrap CLI ngoài.
- Assumption lớn nhất: swift-sdk + tự build sync/adapter đủ nhanh trong Swift. Đã verify SDK official, active.
- Fail đầu tiên khi: cần bám sát tính năng npm-ecosystem quá sát, hoặc swift-sdk lag spec MCP → fallback: stdio JSON-RPC tự viết (nhỏ), engine nằm sau protocol `LibraryEngine` để swap được.
- Worst case: đổi engine sang TS sau, UI + adapter spec giữ nguyên.
- Điểm mạnh: 1 toolchain, zero runtime dependency, 1 artifact ký + notarize, "native" đúng nghĩa đen yêu cầu, tích hợp FSEvents/Keychain trực tiếp.

### B — SwiftUI shell + core TypeScript (hoặc wrap vercel skills + mcpm)
- Mạnh: leverage nhanh nhất (TS SDK MCP là reference impl, simple-git, registry client sẵn); core dùng được cross-platform/CLI-only.
- Yếu: bundle Node/Bun (~60-90MB) hoặc bắt user cài Node; IPC 2 ngôn ngữ; nếu wrap CLI ngoài → vỡ theo mỗi lần họ đổi flag/behavior (skills CLI đang có bug symlink #851/#693 → mình gánh bug của họ).
- Fail đầu tiên khi: debug xuyên 2 runtime, hoặc upstream CLI breaking change.

### C — Tauri/Electron cross-platform
- Fail ngay constraint "native macOS" của user; menu-bar/UX polish kém hơn; chỉ đáng nếu mục tiêu đổi thành cross-platform. Loại.

**So worst-case:** A = chậm hơn lúc đầu nhưng không có sập hệ thống; B = phức tạp vận hành + phụ thuộc upstream; C = sai đề bài. → Chọn **A**, nhỏ nhất mà thỏa contract (KISS), reuse hệ sinh thái ở protocol level (DRY đúng chỗ).

## Tư vấn tính năng bổ sung (câu hỏi 4 của user)

MVP (core value):
1. Adapter matrix data-driven + copy-fallback + hash-sync cho copy mode.
2. `doctor`: phát hiện symlink gãy, orphan, drift config, tự sửa.
3. Version pin + lockfile + atomic swap (`current` symlink) + rollback; xem diff trước update.
4. "Adopt" import hiện trạng: quét skills/MCP đang cài rải rác các app → gom vào library (onboarding "tìm thấy 23 skills / 4 app, 6 bản trùng").
5. GUI + CLI + MCP parity trên cùng core; menu bar quick toggle.

v1.1 (differentiators):
6. Security gate trước install/update: chạy cisco skill-scanner / snyk agent-scan, hiện cảnh báo.
7. Secrets của MCP config vào Keychain, không plaintext env trong JSON.
8. Profiles/Stacks: bundle skills+MCP theo vai trò ("web-dev", "sec-audit"), manifest `agentos.yaml` commit vào repo → teammate `agentos sync` là giống hệt.
9. Deprecation watch: upstream archived/yanked → notify; scheduled sync + FSEvents.
10. Consolidation wizard cho near-dupe (merge/chọn bản tốt hơn).

v2:
11. Team channel = private git repo làm registry nội bộ.
12. Usage analytics local (đọc transcript agent để biết skill nào được dùng thật) — privacy: local-only.
13. Community signals (installs skills.sh, stars) trộn vào quality score; ⌘K palette; Sparkle auto-update; thêm adapter (VS Code, Copilot, Goose, Kiro, Junie, OpenCode, Windsurf, Zed).

## Rủi ro chính
- Symlink không đồng nhất giữa agents (bằng chứng: Codex #8369, Claude Code #14836) → copy-fallback là bắt buộc, không phải nice-to-have.
- Ghi config app khác = chỗ dễ phá nhất: bắt buộc parse-merge + backup + atomic rename.
- Supply-chain: không auto-execute; pin + diff + scan.
- iCloud/Dropbox sync phá symlink nếu user để project trong thư mục sync.
- Naming collision giữa nguồn → namespace `source/skill` (giống `io.github.user/server` của MCP Registry).
- Tên "AgentOS" đã có nhiều dự án trùng (AIOS/agentos.*) → cân nhắc rename khi public.

## Handoff
- Next: `/ak:plan` tạo `plans/260830-0335-agentos-skills-mcp-manager/` — phase 0 = spike verify symlink/copy từng agent thật + handshake swift-sdk; sau đó `/ak:cook`.
- Phase plan/implement được phép trigger `/essential-questions` + deep-research (GitHub/X) per-adapter như user đã ủy quyền.

## Câu hỏi chưa chốt
1. "MCP server chạy native" = MCP interface của chính app (đang giả định) — đúng ý? (Cả 2 cách hiểu đều được thỏa: app không bao giờ yêu cầu Docker.)
2. Danh sách agent đợt đầu chốt: Claude Code, Codex, Grok, Antigravity (+ Claude Desktop cho MCP)? Thêm Cursor/Gemini CLI ngay không?
3. Sản phẩm cá nhân, OSS, hay thương mại? (ảnh hưởng license, telemetry, Developer ID $99/năm.)
4. Team-sharing (private git channel) cần ở MVP hay để v2?
5. macOS tối thiểu 15 hay 26 (để dùng Foundation Models on-device cho near-dupe)? Có cần Intel không?
6. Giữ tên "AgentOS" hay đổi (trùng nhiều dự án)?

## Nguồn chính
- agentskills.io adoption: paperclipped.de/en/blog/agent-skills-open-standard-interoperability/ ; strapi.io/blog/what-are-agent-skills-and-how-to-use-them
- vercel-labs/skills + skills.sh: github.com/vercel-labs/skills ; vercel.com/changelog/introducing-skills-the-open-agent-skills-ecosystem ; issues #851 #693
- MCP Registry: registry.modelcontextprotocol.io ; modelcontextprotocol.io/registry/about
- Swift SDK: github.com/modelcontextprotocol/swift-sdk
- Codex skills: developers.openai.com/codex/skills ; github.com/openai/codex/blob/main/docs/skills.md ; issue #8369
- Claude Code skills: code.claude.com/docs/en/skills ; anthropics/claude-code#14836
- Antigravity: atamel.dev/posts/2026/07-10_where_agy_mcp_servers/ ; medium.com/google-cloud/configuring-mcp-servers-and-skills-for-antigravity-cli-and-ide-a938c7eebb78
- Grok: docs.x.ai/build/features/skills-plugins-marketplaces ; docs.x.ai/build/features/mcp-servers
- Security: github.com/cisco-ai-defense/skill-scanner ; github.com/snyk/agent-scan ; thenewstack.io/ai-agent-skills-security/
- Cạnh tranh macOS: josh.ing/mymcp ; MCP One (App Store id6748261474) ; fleurmcp.com ; mcporchestrator.app ; mcp-bundler.com
