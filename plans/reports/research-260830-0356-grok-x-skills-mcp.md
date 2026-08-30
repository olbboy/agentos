# Raw research — grok CLI (live X + GitHub + web), 2026-08-30

> Provenance: `grok -p` (Grok Build 1.0.13) chạy headless theo ủy quyền của user; nội dung dưới do grok tổng hợp, link X/GitHub chưa verify từng cái. Phục vụ advisory-260830-0356.

Tôi sẽ khảo sát complaint, wish-list và tool thật từ X và web, bắt đầu bằng skill nghiên cứu rồi chạy tìm kiếm song song.Đang chạy `agent-reach doctor` và đọc tài liệu Twitter/web/GitHub trước khi thu thập nguồn.Twitter/GitHub/web đã sẵn sàng. Tôi đang song song tìm complaint, wish-list và tool quản lý skills/MCP.Đã có complaint cốt lõi. Tiếp theo tôi đào GitHub, X và trang tool để xác nhận tên, link và chỗ còn thiếu.Nguồn: live X (keyword + semantic) + web + GitHub (`gh`). `twitter-cli` 404 nên dùng X search native. Thời điểm: 2026-08-30.

---

## 1) TOP ~10 pain points thật

- **Config sprawl / N×M copy.** Mỗi harness một folder: `.claude/skills`, `.cursor/skills`, `.codex/skills` / `.agents/skills`, Antigravity `~/.gemini/config/skills/`. `@ayv4zyan` ([post](https://x.com/ayv4zyan/status/2089995782778765766)): Grok/Codex/Pi/OpenCode dùng `~/.agents/skills/`, Google thì khác. `@xueyu1125` ([post](https://x.com/xueyu1125/status/2093148560309014586)): đổi máy = cài lại skill. Reddit tóm: “spec unified us, paths divided us” ([skill-mix/problems.md](https://github.com/razbakov/skill-mix/blob/main/docs/problems.md)).

- **CLAUDE.md vs AGENTS.md split-brain.** `@tobi` (Shopify, ~19k likes, [post](https://x.com/tobi/status/2092259436538495186)): cân nhắc cấm Claude Code vì không đọc `AGENTS.md` / `.agents/skills`. Monorepo lớn không thể giữ 2 cây file đồng bộ — “complexity tax”. `@AstroHanRay` ([post](https://x.com/AstroHanRay/status/2092870761635864734)): chỉ Claude Code còn cứng `CLAUDE.md`, “ép mọi người dùng symlink”.

- **MCP ăn context trước khi gõ prompt.** `@aakashgupta` ([post](https://x.com/aakashgupta/status/2029409062367199414)): Google Workspace MCP = 142 tools ~37k tokens (~19% cửa sổ 200k); user khác ~98.7k; Cursor hard-cap 40 MCP tools. Practitioner guide: 5 MCP / 58 tools ~55k tokens upfront; skill chỉ ~30–50 tokens đến khi invoke ([codersera](https://codersera.com/blog/claude-skills-mcp-servers-practitioner-guide-2026/)). Scalekit: MCP vs CLI lên tới **32× tokens** (ví dụ 1,365 vs 44,026) ([woshipm](https://www.woshipm.com/ai/5973563.html)). `@sairahul1` ([post](https://x.com/sairahul1/status/2091082195431833747)): MCP/logs dump JSON khổng lồ.

- **Duplicate skill load.** Cursor user: cùng `planning-with-files` load từ **11 path** (Codex + Claude plugin cache + symlink Continue/Factory/…) ([Cursor #150137](https://forum.cursor.com/t/critical-issue-duplicate-skills-loading-causing-context-window-waste-and-confusion/150137), [problems.md](https://github.com/razbakov/skill-mix/blob/main/docs/problems.md)). ruflo: 367 `SKILL.md`, 5× duplicate → “378 descriptions dropped”, full listing ~11k tokens/session ([#1834](https://github.com/ruvnet/ruflo/issues/1834)). `@yusing_wys` ([post](https://x.com/yusing_wys/status/2092338880934797780)): placeholder `disable-model-invocation` để model không thấy 2 list.

- **Symlink gãy / không follow.** `@himkt` ([post](https://x.com/himkt/status/2093616601354625402)): Codex đọc folder symlink nhưng **không nhận `SKILL.md` là symlink**. Claude Code `/skills` bỏ qua symlink dir ([#14836](https://github.com/anthropics/claude-code/issues/14836)). Cursor historically không follow symlink ([forum](https://forum.cursor.com/t/skills-installed-by-skill-sh-will-not-be-found-if-use-symlink-method/151014)). Windows: git checkout symlink thành text file ([caveman #150](https://github.com/JuliusBrussee/caveman/issues/150)). Absolute symlink trong repo skill → `ENOENT` abort install ([vercel-labs/skills #583](https://github.com/vercel-labs/skills/pull/583)). WSL: skills-manager fallback copy, drift ([#147](https://github.com/xingkongliang/skills-manager/issues/147)).

- **Security / supply chain.** Protego 2026: **13.4% skill critical**, **36.8% có lỗ hổng**; skill `llm-council` đọc cả `.env` ([protego](https://protego.me/blog/claude-code-skills-mcp-security-risks-2026)). OX: 9/11 MCP registry poison được; Trend Micro: 492 MCP server public không auth. MCPTox: tool-poisoning ASR >60%, worst 72%. arXiv:2510.26328: **26.1% / 42,447 marketplace skills** vulnerable. `@FlorisNexus` ([post](https://x.com/FlorisNexus/status/2090779741187924257)): approve `cp` vào symlink MCP config — **Claude Code, Codex, Cursor, Copilot, Gemini CLI, Grok Build: 6/6**. `@robinebers` ([post](https://x.com/robinebers/status/2005201812144750937)): phần lớn skill marketplace vô dụng, một số nguy hiểm như MCP insecure. `@coingyy` ([post](https://x.com/coingyy/status/2093126725571920224)): “everyone shares skills, nobody checks if they’re safe.”

- **Version drift / lockfile yếu.** agentskills#46: metadata một version, script version khác; pin/lockfile không chuẩn ([problems.md](https://github.com/razbakov/skill-mix/blob/main/docs/problems.md)). `npx skills update` biến `--copy` thành symlink, gãy git Windows ([#1199](https://github.com/vercel-labs/skills/issues/1199)). skills-manager sync “success” nhưng Kimi đọc folder khác ([v1.35.0](https://github.com/xingkongliang/skills-manager/releases/tag/v1.35.0)). MCP JSON sai 1 dấu phẩy → **tắt hết server** ([codersera](https://codersera.com/blog/claude-skills-mcp-servers-practitioner-guide-2026/)).

- **Team sharing / không có org push.** Skill claude.ai là per-user, không sync API/Code ([wearetandem](https://www.wearetandem.ai/en/blog/ai-applied/claude-skills-end-of-prompt-engineering)). Codex: skill trong repo **force-on cho cả team**, không có default-off/opt-in như Claude `enabledPlugins` ([openai/codex #34328](https://github.com/openai/codex/issues/34328)). `@nchgnzlz` ([post](https://x.com/nchgnzlz/status/2091461187519037705)): Claude marketplace = người khác model bị out. Skills Over MCP ra đời vì “copy-paste dance” ([DEV](https://dev.to/spencerpauly/introducing-skills-over-mcp-the-better-way-to-share-and-distribute-skills-bb)).

- **Cùng `SKILL.md` ≠ cùng hành vi.** `@YanqingCheng` ([post](https://x.com/YanqingCheng/status/2092558710107263214)): Codex+GPT over-trigger skill; Claude under-trigger — phải sửa description. Agent Plugins 1.0 (Aug 2026) chuẩn hóa **folder**, không chuẩn hóa install/secrets/provenance; Anthropic **không** ngồi TSC; Antigravity vẫn `mcp_config.json` riêng ([@akshay_pachaar](https://x.com/akshay_pachaar/status/2085791632457433119), [New Stack](https://thenewstack.io/agent-plugins-portability-gaps/)).

- **Silent drop + activation fail + CLAUDE.md bloat.** Skill listing budget ~1–2%; dư thì **cắt description im lặng**. Skill không auto-invoke (Claude #11266/#19308). Addy Osmani: file agent >200 dòng, token ↑, agent **xấu hơn**; study 100 repo: lint leak 62%, context bloat 42%, skill leak 35% ([substack](https://addyo.substack.com/p/audit-your-agent-files)). `@ryan_doser13` ([post](https://x.com/ryan_doser13/status/2092628204267688345)): skill phình là chết. `@rk625dev` ([post](https://x.com/rk625dev/status/2091624003467460768)): Antigravity GitHub MCP đòi PAT, không OAuth.

---

## 2) TOP ~10 feature người ta muốn ở app quản lý skills/MCP

- **Một library, nhiều client — symlink hoặc copy, toggle per-agent.** `@CasJam` ([post](https://x.com/CasJam/status/2093086066114969647)): `.agents/skills` + `AGENTS.md`, không `.claude/`. `@xueyu1125`: soft-link + Git private repo + custom agent. `@31Carlton7` ([post](https://x.com/31Carlton7/status/2093101207917396134)): “Homebrew for MCP” — import sẵn có, backup trước khi ghi, checkbox per client.

- **Native đọc `AGENTS.md` + `.agents/skills` (không symlink hack).** Demand từ `@tobi`; Agent Plugins 1.0 chỉ cover packaging, không thay CLAUDE.md.

- **Auth một lần, token/OAuth gateway, IdP enterprise.** Claude enterprise-managed MCP auth GA ([@ClaudeDevs](https://x.com/ClaudeDevs/status/2091953609185657251)); Carlton: “Sign in to Notion once, every client gets the token.” Agent Plugins **cấm embed secret**, không có field credential portable.

- **Dedup + context budget UI.** Dedup theo `name`, latest-wins, whitelist scan dir; hiện token/tool count **trước** khi bật MCP (Cursor 40-tool cap, `/context`). `@yusing_wys`: user `/skill` được, model không thấy duplicate catalog.

- **Security scan + lockfile + “approve resolved path”.** Hash skill/MCP/plugin/hook vào git (Eyebrow narrative trên X); scan malware/exfil/prompt-injection trước install; resolve symlink trước khi user approve (`@FlorisNexus`).

- **Team sync: Git + default-off + per-contributor opt-in.** Codex #34328; Skills-over-MCP remote `skills/list` + digest (`@Voxyz_ai` [post](https://x.com/Voxyz_ai/status/2092952771150680387) — Codex đọc skill từ MCP, không copy máy).

- **Profile theo session: bật MCP/skill theo task, không always-on.** mcpm.sh profiles; CCO context budget; “few MCP, many thin skills”.

- **Lockfile pin version + nhớ install mode (symlink vs copy).** `skills-lock.json` vẫn experimental; #1199: lock không lưu `--copy`.

- **Health + log MCP I/O + unified permissions.** `@dorianmariecom` ([post](https://x.com/dorianmariecom/status/2093679779941597225)): Codex nên hiện input/output MCP. `@ZappoMan` ([post](https://x.com/ZappoMan/status/2091731862255530364)): watcher connect, PAT cho client không OAuth, client logging. `@stretchcloud` ([post](https://x.com/stretchcloud/status/2092994295011688473)): unified permission, session continuity, cost dashboard đa backend.

- **MCP → skill/CLI mỏng + marketplace agent-installable.** Google `gws` CLI tránh 37k tool tokens; one-mcp export MCP thành Skills; `@VKAIZoneIL` ([post](https://x.com/VKAIZoneIL/status/2089632956121829744)): “import and sync all skills and mcps from Claude/ChatGPT/Grok.”

---

## 3) Tool người ta thật sự recommend — GitHub + chỗ thiếu

| Tool | Stars (gh, ~2026-08-30) | Dùng để | Thiếu |
|---|---|---|---|
| [vercel-labs/skills](https://github.com/vercel-labs/skills) (`npx skills`, skills.sh) | **~30k** | Installer de-facto: 70+ agent, lockfile, `.agents/skills` | Không phải dashboard MCP; `update` phá `--copy` → symlink; Cursor/Codex historically không follow symlink; lockfile experimental |
| [xingkongliang/skills-manager](https://github.com/xingkongliang/skills-manager) | **~4.2k** | Desktop 50+ agent (Claude/Codex/Cursor/Gemini/Grok/Antigravity), marketplace, Git backup. `@Pentiminax`, `@xueyu1125`, `@jin_lifelab` | MCP không phải core; WSL symlink → copy drift; SQLite crash nếu xóa folder tay ([#147](https://github.com/xingkongliang/skills-manager/issues/147)); từng sync nhầm path Kimi |
| [runkids/skillshare](https://github.com/runkids/skillshare) | **~2.6k** | CLI Go, 49+ tool, `.skillignore`, Git sync, `skillshare ui` | MCP/config JSON không phải job chính; vẫn phụ thuộc symlink host |
| [mcp-router/mcp-router](https://github.com/mcp-router/mcp-router) | **~2.1k** | Desktop MCP: project/workspace, bật/tắt tool | Không quản skill; extra hop/daemon; không phải Git team pack |
| [qufei1993/skills-hub](https://github.com/qufei1993/skills-hub) | **~1.2k** | Desktop “install once, sync everywhere” | MCP/security/lockfile nông hơn skills-manager |
| [MoizIbnYousaf/Ai-Agent-Skills](https://github.com/MoizIbnYousaf/Ai-Agent-Skills) | **~1.1k** | `npx ai-agent-skills`, 12+ runtime | Catalog installer, không lifecycle MCP |
| [pathintegral-institute/mcpm.sh](https://github.com/pathintegral-institute/mcpm.sh) | **~993** | CLI MCP: registry, profile, router, doctor | Không skill; GitHub MCP env Docker từng 401 ([#270](https://github.com/pathintegral-institute/mcpm.sh/issues/270)); docs router phức tạp |
| [jiweiyeah/Skills-Manager](https://github.com/jiweiyeah/Skills-Manager) | **~970** | Desktop MIT, 32 tool, symlink | Trùng niche skills-manager; MCP/security mỏng |
| [luongnv89/asm](https://github.com/luongnv89/asm) | **~902** | Universal skill manager CLI | MCP/team Git yếu hơn skillshare |
| [wanghuan9/skilldock](https://github.com/wanghuan9/skilldock) | **~496** | Skills **+ MCP + plugins**, Git diff | Ít sao hơn; chưa “standard” như vercel CLI |
| [RealZST/HarnessKit](https://github.com/RealZST/HarnessKit) | **~418** | Skills+MCP+plugins+hooks+CLI; Antigravity skills/MCP | Plugin/hooks Antigravity = “—”; cộng đồng nhỏ |
| [mcpware/cross-code-organizer](https://github.com/mcpware/cross-code-organizer) | **~376** | Scan duplicate, move MCP/skill, security, context budget, backup (Claude+Codex) | Không phải installer marketplace; Gemini/Grok/Antigravity nông hơn |
| [milisp/mcp-linker](https://github.com/milisp/mcp-linker) | **~322** | GUI sync MCP + official registry | Skills secondary; login/subscribe trên README |
| [OldJii/mcp-dock](https://github.com/OldJii/mcp-dock) | **~225** | 14 client, 8500+ MCP, 4400+ skills | Catalog lớn → chính là bloat nếu bật hết |
| [mcp360/mTarsier](https://github.com/mcp360/mTarsier) | **~49** | MCP+skills local, deep link, export/import | Windows path sai ([#27](https://github.com/mcp360/mTarsier/issues/27)); Codex/ChatGPT Desktop merge ([#28](https://github.com/mcp360/mTarsier/issues/28)) |
| [31Carlton7/mcp-manager](https://github.com/31Carlton7/mcp-manager) | **~1** (mới tweet) | Menubar + OAuth gateway, 4 client | **macOS 26+ only**; chưa Gemini/Grok/Antigravity |
| [xjeway/mcp-manager](https://github.com/xjeway/mcp-manager) | **~6** | Cross-platform MCP config, có Antigravity/Gemini | v1 **không** runtime/health; skills không phải core |
| [Skills Over MCP](https://skillsovermcp.com/) ([template](https://github.com/spencerpauly/skills-repo)) | hosted | Repo `SKILL.md` → MCP URL cho team | Public-first; skill-as-tool lại tốn schema tokens; SEP-2640 **chưa land** ([MCP discussion](https://github.com/modelcontextprotocol/modelcontextprotocol/discussions/2994)) |

Khác (recommend theo use-case, không phải “manager app” đầy đủ): [Agent Plugins spec](https://github.com/agentplugins/agent-plugins-spec) — packaging, **không** install/secrets/provenance; [Composio MCP Gateway](https://composio.dev/content/best-mcp-servers-claude-code-codex) — 1 router SaaS, không local skill Git; [burugo/one-mcp](https://github.com/burugo/one-mcp) (~412) — reverse-proxy + export Skills; [yusing/skills-mgr](https://github.com/yusing/skills-mgr) — niche anti-duplicate; [kwonye/mcpx](https://github.com/kwonye/mcpx) — install/auth once (rất mới).

---

**Tín hiệu 2026:** format (`SKILL.md` / agentskills.io / Agent Plugins) đã gần thống nhất; **path, symlink, secrets, lockfile, org rollout, context tax MCP** thì chưa. App thắng = 1 source of truth + toggle per client + Git team + scan bảo mật + hiện token **trước** khi bật — không phải marketplace skill thứ 50.

Câu chưa resolve từ nguồn công khai: Eyebrow lockfile có adoption thật ngoài crypto-promo X không; Claude Code sẽ join Agent Plugins TSC khi nào; Grok Build skill path có ổn định `~/.agents/skills` hay còn fork nội bộ.
