# AgeOS

**One library for your Agent Skills and MCP servers — distributed to every coding agent on your Mac.**

Your skills are scattered: `~/.claude/skills`, `~/.codex/skills`, `~/.agents/skills`, `~/.grok/skills`, plugin caches… The same skill installed three times, updated in none. Every catalog entry silently eats context tokens in every session. AgeOS fixes the whole loop:

- **One source of truth** — versioned library at `~/.ageos/`, pulled from GitHub repos (agentskills.io standard) or local folders. Update once, every agent follows.
- **Data-driven adapters** — each agent is a JSON file (path, symlink capability, MCP config format). Symlink where the agent supports it, copy-with-manifest where it doesn't. Adding an agent = adding JSON, no release needed.
- **Intelligence** — effective-load map (which agent loads what, from where), exact + near duplicate detection (on-device embeddings, nothing leaves your Mac), deprecated flags, quality scores, description linter.
- **Context Budget Meter** — estimates the always-loaded catalog tokens per agent (±20%) and warns before you drown your context.
- **Safety first** — never overwrites files you created, never regenerates client configs (parse-merge only), backs up before every config write, static-only scanning (skill content is never executed), reversible everything.

Three surfaces, one core: **SwiftUI app** (menu bar included) · **CLI `ageos`** (full `--json`) · **MCP server `ageos-mcp`** so your agents can manage their own skills.

Native Swift 6, macOS 26+. No Node, no Docker, no runtime.

## Quickstart (CLI)

```bash
# Build & install (Homebrew cask coming with v0.1.0)
swift build -c release
mkdir -p ~/.ageos/bin && cp .build/release/ageos .build/release/ageos-mcp ~/.ageos/bin/
export PATH="$HOME/.ageos/bin:$PATH"

# Pull a skill library
ageos source add https://github.com/anthropics/skills

# See your machine's real state
ageos adopt              # who loads what, from where, duplicates included
ageos scan               # exact + near dupes, deprecated, description lint
ageos budget             # always-loaded tokens per agent

# Distribute
ageos enable canvas-design --target claude-code     # symlink
ageos enable canvas-design --target codex           # copy + manifest (codex ignores file symlinks)
ageos doctor --fix                                  # repair drift anytime

# MCP servers
ageos mcp search context7
ageos mcp add io.github.upstash/context7
ageos mcp enable context7 --target claude-code
ageos mcp health context7

# Let your agent self-serve
ageos mcp add --manual ageos --command ~/.ageos/bin/ageos-mcp
ageos mcp enable ageos --target claude-code
# → Claude Code gets: search_skills, install_skill, enable_skill, budget_report, doctor…
```

## Supported agents (wave 1)

| Adapter | Skills | MCP | Mode | Verified on real machine |
|---|---|---|---|---|
| claude-code | `~/.claude/skills` | `~/.claude.json` + project `.mcp.json` | symlink | ✅ |
| codex | `~/.codex/skills` | `~/.codex/config.toml` | copy (folder-symlink works; copy kept for safety) | ✅ |
| grok | `~/.grok/skills` | `~/.grok/config.toml` | symlink (file symlinks too) | ✅ |
| antigravity | `~/.gemini/config/skills` | `~/.gemini/config/mcp_config.json` | symlink | ⚠ filesystem evidence, no headless CLI to verify |
| claude-desktop | — | `claude_desktop_config.json` | mcp-only | ✅ |
| universal | `~/.agents/skills` (read by codex, grok, cursor, …) | — | symlink | ✅ |

Adapters live in [`adapters/`](adapters) as plain JSON — **contributing a new agent is a JSON pull request** (see [CONTRIBUTING.md](CONTRIBUTING.md)).

## Security stance

- Skill content is **never executed** during scan/score/budget (verified by a booby-trap test).
- Client configs are **parse-merged**, never regenerated; unknown keys and your own entries survive untouched; timestamped backups before every write (`ageos mcp restore-backup`).
- AgeOS only removes things it created (lockfile + `dev.ageos.managed` xattr double-check).
- MCP env secrets are plaintext in client configs at MVP (same as the clients themselves) and flagged `sensitive` in the lockfile — Keychain storage is the v1.1 milestone.

See [SECURITY.md](SECURITY.md).

## Development

```bash
swift build && swift test          # core + CLI + mcp-server (68 tests)
cd apps/AgeOS && xcodegen generate # SwiftUI app
xcodebuild -project AgeOS.xcodeproj -scheme AgeOS build
```

Docs: [architecture](docs/system-architecture.md) · [codebase summary](docs/codebase-summary.md) · [deployment](docs/deployment-guide.md) · [PDR](docs/project-overview-pdr.md)

## License

[MIT](LICENSE)
