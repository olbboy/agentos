# Contributing to AgeOS

## Dev setup

```bash
git clone <repo> && cd agentos
swift build && swift test        # core + CLI + ageos-mcp (Swift 6.3+, Xcode 26+)
cd apps/AgeOS && xcodegen generate && xcodebuild -scheme AgeOS build
```

Tests never touch your real `$HOME` — everything runs through a temporary `AGEOS_HOME`. Keep it that way: any test that needs paths gets them from `withTempHome`/`FakeAgentWorld` helpers.

Note: the app UI smoke test (`AgeOSUITests`) drives the real app — the first `xcodebuild test` run needs you to approve the macOS Automation permission prompt once (interactive session required).

## The main contribution path: adapters (JSON only)

Each supported agent is one JSON file in [`adapters/`](adapters) — **no Swift required**:

```jsonc
{
  "schemaVersion": 1,
  "id": "my-agent",                      // kebab-case, unique
  "displayName": "My Agent",
  "detect": ["~/.my-agent"],             // any existing path ⇒ agent present
  "skills": {
    "globalPath": "~/.my-agent/skills",
    "projectPath": ".agents/skills",     // relative to project root, or null
    "compatPaths": [],                   // extra dirs the agent ALSO reads (for effective-load scan)
    "folderSymlink": true,               // measured, not assumed — see checklist
    "fileSymlink": false,
    "preferredMode": "symlink",          // "symlink" | "copy"
    "verified": false                    // true ONLY with real-machine evidence
  },
  "mcp": {                               // or null if the agent has no MCP support
    "configPath": "~/.my-agent/config.json",
    "format": "json",                    // "json" | "toml"
    "keyPath": "mcpServers",
    "verified": false
  },
  "budget": { "catalogTokensWarn": 15000, "descriptionTruncateChars": 0 },
  "notes": "Evidence: how you verified, date, agent version."
}
```

### Verification checklist (required for `verified: true`)

1. Create a probe skill (`ageos-spike-probe`) with a unique description marker.
2. **Folder symlink**: symlink its folder into `globalPath` → confirm the agent lists/uses it (agent's own listing command, render-prompt debug, or one headless run). Remove the symlink.
3. **File symlink**: real folder, symlinked `SKILL.md` → same check.
4. **Project scope**: repeat under `projectPath` in a scratch project.
5. **MCP**: add a dummy entry via AgeOS, confirm the agent's `mcp list`/inspect sees it, then `ageos mcp disable` and confirm your config is byte-identical to the automatic backup.
6. Paste the evidence (commands + output snippet + agent version + date) into `notes`.

Un-verified values from documentation are welcome too — just keep `verified: false` so `doctor` re-checks at runtime.

Users can test your adapter before it ships: drop the JSON into `~/.ageos/adapters/` (same id overrides the bundled one).

## Code contributions

- Swift 6 strict concurrency; PascalCase files, kebab-case directories.
- Every path comparison goes through `canonicalPath` (macOS `/var` vs `/private/var` — we learned the hard way).
- Safety invariants are non-negotiable and covered by tests:
  - never overwrite/delete anything AgeOS did not create;
  - never regenerate a client config (parse-merge only), backup before write;
  - never execute skill content during scans.
- `swift test` green before PR; add tests for behavior you add or change.
- Conventional commits (`feat:`, `fix:`, `docs:`…).

## Releases

Maintainers: see [docs/deployment-guide.md](docs/deployment-guide.md) (release lane, notarization, Homebrew cask).
