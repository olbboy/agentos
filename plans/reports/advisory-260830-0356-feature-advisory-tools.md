# Advisory — Tính năng hoàn thiện AgentOS + chọn tool (evidence-based)

- Date: 2026-08-30 03:56 (+07)
- Type: feature advisory (mở rộng mục "Tư vấn tính năng" của `brainstorm-260830-0335-agentos-skills-mcp-manager.md`; phần trùng thì bản này thắng)
- Evidence: X + GitHub qua grok CLI (raw: `research-260830-0356-grok-x-skills-mcp.md`) + WebSearch/WebFetch (vercel skills issues, MyMCP, mcpm, MCPB, NLContextualEmbedding)
- Method: skill `essential-questions` (Quick-Start) → charter dưới

## Inquiry Charter (rút gọn)

- MODE: EVALUATE/SOLVE. Type: JUDGMENT.
- Master question: "Ngoài 3 tính năng lõi user nêu, cần thêm gì để AgentOS hoàn chỉnh, và mỗi nhu cầu kỹ thuật dùng tool/giải pháp có sẵn nào?"
- ★★★ Q1 [RESEARCH] Dev thật đang đau gì? → ĐÃ TRẢ LỜI (mục Pain points).
- ★★★ Q2 [RESEARCH] Đối thủ có gì/thiếu gì? → ĐÃ TRẢ LỜI (mục Landscape).
- ★★★ Q3 [FACT] Tool nào cho từng năng lực? → ĐÃ TRẢ LỜI (bảng chọn tool).
- ★ Q4 [JUDGMENT] Feature nào bắt buộc vs nice-to-have? → mục Ưu tiên.
- ★ Q5 [JUDGMENT] Khác biệt đủ sống cạnh `npx skills` miễn phí? → mục Định vị.
- ⬜ Q6 [PRIMARY] Sẵn lòng trả tiền / ưu tiên cá nhân Leo → không kết luận được từ desk research, để cuối.
- Assumptions đã soi: pain còn tồn tại dù vendor tự vá (chọn feature cross-agent vendor không làm); mọi feature thêm = chi phí bảo trì adapter vĩnh viễn → cần data-driven adapter + doctor.

## Pain points đã xác nhận (X + GitHub, 30/8/2026)

1. Config sprawl N×M: mỗi harness một path (`.claude/skills`, `.agents/skills`, `~/.gemini/config/skills`…); đổi máy = cài lại.
2. CLAUDE.md vs AGENTS.md split-brain (post @tobi ~19k likes: cân nhắc cấm Claude Code vì không đọc AGENTS.md).
3. **Thuế context của MCP**: 1 MCP Google Workspace ~37k tokens trước khi gõ prompt; case ~98.7k; Cursor cap 40 tools; MCP vs CLI chênh tới 32×; skill chỉ ~30–50 tokens tới khi invoke.
4. **Duplicate load đa path**: 1 skill load từ 11 path (Codex + plugin cache + symlink); 367 SKILL.md → "378 descriptions dropped", catalog ~11k tokens/session (ruflo #1834).
5. Symlink lởm khởm: Codex nhận folder-symlink nhưng KHÔNG nhận `SKILL.md` là file-symlink; Cursor từng không follow; `npx skills update` biến `--copy` ngược lại thành symlink (#1199); absolute symlink trong repo → crash install (#583).
6. Security/supply-chain: 36.8% skill công khai có lỗ hổng, 13.4% critical (Protego); 26.1%/42,447 marketplace skills vulnerable (arXiv:2510.26328); attack "approve `cp` vào symlinked MCP config" qua mặt 6/6 agent (@FlorisNexus).
7. Version drift/lockfile yếu: metadata 1 version script version khác; `skills-lock.json` experimental, không nhớ install-mode.
8. Team: Codex repo-skills force-on cả team, không opt-in (#34328); skill claude.ai per-user không sync.
9. Cùng SKILL.md ≠ cùng hành vi (Codex over-trigger, Claude under-trigger) → cần lint description.
10. Silent drop + agent-file bloat: budget catalog ~1–2%, dư là cắt im lặng; agent file >200 dòng làm agent tệ đi (Addy Osmani).
- Chuẩn mới: **Agent Plugins 1.0 (8/2026)** chuẩn hóa packaging plugin (skills/MCP/hooks) nhưng KHÔNG cover install/secrets/provenance; Anthropic chưa ngồi TSC.

## Landscape — sửa nhận định brainstorm

Nhận định cũ "chưa ai gộp skills+MCP" SAI một phần. Thực tế (stars ~30/8):
| Tool | Gì | Thiếu (→ cơ hội của ta) |
|---|---|---|
| vercel-labs/skills `npx skills` ~30k★ | installer de-facto, 70+ agent, skills.sh | không dashboard MCP; update phá `--copy`; lockfile experimental |
| xingkongliang/skills-manager ~4.2k★ | desktop 50+ agent (có Grok/Antigravity), marketplace, Git backup | MCP không phải core; WSL copy-drift; SQLite crash khi user xóa folder tay |
| runkids/skillshare ~2.6k★ | CLI Go, Git sync, TUI | MCP/config phụ; vẫn kẹt symlink host |
| mcp-router ~2.1k★ / mcpm ~1k★ / mcp-linker ~322★ | MCP manager/router/profiles | không skills |
| wanghuan9/skilldock ~496★, RealZST/HarnessKit ~418★ | CÓ gộp skills+MCP(+plugins/hooks) | cộng đồng nhỏ, Antigravity chưa đủ, không intelligence |
| mcpware/cross-code-organizer ~376★ | scan duplicate + security + context budget | chỉ Claude+Codex, CLI, không installer |
| 31Carlton7/mcp-manager (mới) | menubar + OAuth gateway | macOS 26+ only, 4 client, không skills |
| OldJii/mcp-dock ~225★ | catalog 8500 MCP + 4400 skills | catalog to = bloat, không budget/scan |

→ Kết luận định vị (khớp tín hiệu X): app thắng KHÔNG phải marketplace thứ 50, mà là: **1 source of truth + toggle per-client + Git team default-off + security scan + HIỆN TOKEN TRƯỚC KHI BẬT** — đóng gói native macOS (menu bar, Keychain, FSEvents, ký + notarize, nhẹ hơn Electron) + MCP server để agent tự phục vụ. Chưa ai có combo này.

## Tính năng bổ sung MỚI (evidence → feature)

MVP thêm/nâng:
1. **Context Budget Meter** (killer #1): ước lượng token của từng skill (metadata luôn-tải vs body lazy) và từng MCP (schema tools) TRƯỚC khi bật; dashboard budget per-client; cảnh báo cap (Cursor 40 tools) + nguy cơ "silent description drop". Evidence: pain #3, #4, #10.
2. **Effective-load scan**: quét cái agent THẬT SỰ load (mọi path + plugin cache), không chỉ dedupe trong library — giải bài "1 skill/11 path". Gộp với "Adopt" import.
3. **Lockfile nhớ install-mode**: pin version + `linkMode: symlink|copy` per target; adapter khai báo capability symlink cấp folder vs file (Codex chỉ nhận folder-symlink). Sửa lớp bug #1199.
4. **Description linter**: cảnh báo description gây over/under-trigger + quá dài (pain #9, #10).

v1.1 thêm/nâng:
5. **Security gate nâng cấp**: scan trước install (tích hợp cisco skill-scanner / snyk agent-scan nếu có + ruleset built-in: đọc .env, curl|bash, exec bit, symlink ẩn trong repo skill); resolve symlink trên path nhạy cảm trước khi cho approve (chặn attack 6/6); hash/provenance pin trong git.
6. **Secrets vào Keychain**: env của MCP config không nằm plaintext; inject lúc ghi config. (Agent Plugins cấm embed secret mà không có chỗ chứa — ta có.)
7. **Team pack default-off**: channel = private git repo; per-contributor opt-in (đúng nỗi đau Codex #34328); export/import pack.
8. **Format interop**: import `.mcpb` bundle, Agent Plugins 1.0 package, `skills-lock.json` của vercel; không phát minh format mới.

v2:
9. OAuth/auth broker "đăng nhập 1 lần, mọi client dùng token" (validated bởi mcp-manager của Carlton; phức tạp — để sau).
10. **Serve skills qua MCP** (`skills/list` kiểu Skills-over-MCP) khi SEP-2640 land — phân phối không cần chạm disk.
11. MCP→thin-CLI advisor: gợi ý thay MCP nặng bằng CLI/skill mỏng kèm ước tính token tiết kiệm (pattern `gws` CLI, 32×).
12. MCP I/O log viewer + unified permission view; usage analytics local; community signals vào quality score.

(Giữ nguyên từ brainstorm: doctor/drift repair, atomic update+rollback, profiles/stacks, deprecation watch, adapters data-driven, GUI+CLI+MCP parity, menu bar.)

## Bảng chọn tool/giải pháp (Q3 — cho app Swift native)

| Nhu cầu | Chọn | Vì sao | Dự phòng |
|---|---|---|---|
| MCP server+client | modelcontextprotocol/swift-sdk | official, spec 2025-11-25, stdio ổn | tự viết stdio JSON-RPC (nhỏ) |
| CLI | swift-argument-parser | chuẩn Apple | — |
| YAML frontmatter / Markdown | Yams / swift-markdown | thư viện xác lập | — |
| Index DB | GRDB.swift (SQLite) | bền, migration tốt; FS vẫn là source of truth | SwiftData (không khuyên) |
| Near-dupe embedding | NLContextualEmbedding (NaturalLanguage, on-device) + cosine | zero dependency, privacy | model2vec.swift / VecturaKit nếu chất lượng thiếu |
| Ước token (budget meter) | heuristic ~chars/4 + bảng hệ số per-model | đủ cho cảnh báo tương đối | bundle BPE tokenizer sau |
| Watch thay đổi | FSEventStream | native | — |
| Secrets | Keychain Services (wrapper KeychainAccess) | đúng chuẩn macOS | — |
| Fetch nguồn | URLSession + GitHub tarball API | không bắt buộc git | shell `git` nếu có |
| Registry MCP | registry.modelcontextprotocol.io API + `.mcpb` + mcpm registry | chuẩn chính thức | — |
| Nguồn skills | GitHub + skills.sh index + Agent Plugins packages | ecosystem de-facto | — |
| Security scan | adapter "bring-your-scanner" (cisco skill-scanner, snyk agent-scan) + ruleset Swift built-in | không tự viết scanner sâu (DRY) | — |
| Auto-update | Sparkle 2 | chuẩn ngoài MAS | — |
| Phân phối | Developer ID + notarytool + Homebrew cask + DMG | dev-first | — |
| UI | SwiftUI + MenuBarExtra | native, nhẹ | — |

## Ưu tiên chốt (bản hợp nhất)

- MVP: sources+library+lockfile(install-mode) → adapters (Claude Code, Codex, Grok, Antigravity, Claude Desktop; symlink/copy per capability) → Adopt + effective-load scan + dedupe exact/near → **Context Budget Meter** → doctor → GUI+CLI+MCP server (search/install/enable/scan) → menu bar.
- v1.1: security gate + Keychain secrets + team pack default-off + profiles + deprecation watch + description linter + interop (.mcpb/Agent Plugins/skills-lock).
- v2: OAuth broker, serve-skills-over-MCP, MCP→CLI advisor, I/O logs, analytics, ratings cộng đồng, thêm adapter.

## Câu hỏi chưa chốt

1. Q6 [PRIMARY]: sản phẩm cá nhân/OSS/thương mại — quyết cách làm team pack + telemetry (không suy ra được từ desk research).
2. Grok Build path skill ổn định `~/.grok/skills` hay chuyển hẳn `~/.agents/skills`? (nguồn mâu thuẫn; verify khi làm adapter — phase 0 spike.)
3. Claude Code có join Agent Plugins TSC / đọc `.agents/skills` không? (theo dõi; ảnh hưởng độ bền adapter.)
4. SEP-2640 (skills qua MCP) land khi nào? (gate cho feature v2 #10.)
5. Danh sách agent đợt đầu + minOS (15 vs 26) + tên thay "AgentOS" (trùng Fiserv agentOS 5/2026, AgentOS Sapienx) — cần Leo chốt.
