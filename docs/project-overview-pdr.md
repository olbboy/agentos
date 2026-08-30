# AgeOS — Project Overview / PDR

## Problem
Skills and MCP servers are fragmented across agents — claude-code, codex, grok,
antigravity, claude-desktop. Measured on a real dev machine on 2026-08-30: 169
distinct skills, 345 load entries, 147 skills present in two or more agents, 18
exact-duplicate pairs, and claude-code carrying roughly 10k always-loaded catalog
tokens. No tool manages that centrally, and none of them measures what it costs
in context.

## Product
A native macOS manager (Swift 6, macOS 26+): one central library at `~/.ageos/`,
data-driven adapters that distribute per agent, intelligence over the result
(duplicates, deprecation, quality, budget), and three surfaces — a SwiftUI app,
the `ageos` CLI, and the `ageos-mcp` MCP server.

## Users
Developers running two or more coding agents on macOS, and power users who want
to manage skills the way they manage dependencies.

## Differentiators
1. **Effective-load map** — shows what is actually loaded, including compat paths
   and plugin caches.
2. **Context Budget Meter** per agent (±20%).
3. **Adapters are JSON**, so contributing a new agent needs a pull request, not a
   release.
4. **Safety invariants**: never touch what the user made, parse-merge configs
   with a backup before every write, static-only scanning.

## Decisions (settled during plan validation, 2026-08-30)
- MIT licensed. Named AgeOS; the repository directory stays `agentos`.
- macOS 26+. FoundationModels is optional — the keyword fallback is the primary
  path, not a degraded one.
- Six wave-1 adapters: claude-code, codex, grok, antigravity, claude-desktop,
  universal-agents.
- TOML writes go through TOMLKit: normalize, warn, and back up. A line-targeted
  editor is the replan trigger if the community pushes back.
- MCP secrets are plaintext at MVP and flagged `sensitive`; Keychain storage is
  the v1.1 milestone.
- Codex uses `preferredMode = copy`. Folder symlinks were verified working on
  2026-08-30, so flipping this is a data update once openai/codex#8369 settles.

## Status
v0.1.0 is published: tagged, released on GitHub, and available through the
`olbboy/homebrew-tap` cask. The build is unsigned, so Gatekeeper needs the
quarantine attribute stripped — see `deployment-guide.md`.

Since v0.1.0 the app has been through a UI redesign: a token layer with light,
dark and high-contrast variants, five shared components, an Overview screen that
has real content on first launch, Scan and Doctor merged into one Diagnostics
screen ordered by severity, and every string in the app, core and CLI moved to
English on a String Catalog.

Detail: `plans/260830-0405-ageos-mvp/` and `plans/260830-0851-ageos-ui-redesign/`.

## Roadmap after v0.1.0
Keychain secrets (v1.1) · foundation-model classification refinement ·
line-targeted TOML if it proves necessary · community adapters · Sparkle updates
(needs a Developer ID).
