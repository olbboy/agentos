# AgeOS — System Architecture

## Overview

```
┌─ SwiftUI app (apps/AgeOS) ─┐  ┌─ CLI ageos ─┐  ┌─ ageos-mcp (stdio) ─┐
│  AppModel (@Observable)    │  │ ArgumentPar.│  │ swift-sdk, 9 tools  │
└─────────────┬──────────────┘  └──────┬──────┘  └─────────┬───────────┘
              └────────────── AgeOSCore (SPM lib) ─────────┘
   store/ · skill-model/ · sources/ · lockfile/ · index/ · adapters/
   link-engine/ · doctor/ · mcp/ · config-writers/ · intelligence/
```

**The filesystem is the source of truth.** SQLite (`index.sqlite`, GRDB) is only
a cache — `ageos reindex` rebuilds it from the filesystem. The lockfile
`ageos.lock.json` remembers versions and where each thing was enabled (targets
carry scope, linkMode and path).

## `~/.ageos/` layout
```
library/skills/<ns>/<name>/<version>/ + current→   # ns = owner/repo | local/<slug>
library/mcp/<ns>/<name>/<version>/                  # .mcpb payload
adapters/          # user override (a matching id beats the bundled spec)
backups/<ts-ms>/   # the client config before EVERY write
adopted/           # skills imported by `ageos adopt --import`
bin/               # locally installed ageos + ageos-mcp
index.sqlite · sources.json · ageos.lock.json · mcp-servers.json · cache/
```

## Main flows

**Sync**: `SourceProvider.fetch` (GitHub tarball with ETag/sha, local
content-hash) → `SkillScanner` (`**/SKILL.md`, at most 4 levels deep) → validate
→ `Store.installVersion` (atomic rename) → `setCurrent` (atomic symlink swap) →
`LinkEngine.propagateVersionChange` (copy targets re-sync, drift respected) →
index upsert.

**Enable**: the `AdapterSpec` decides the mode. Symlink links to
`library/.../current`, so a version swap propagates on its own. Copy runs
`CopySync` plus `.ageos-manifest.json` (sha256 per file) and the
`dev.ageos.managed` xattr. Preflight: if the destination exists and AgeOS did not
create it, the operation is REFUSED.

**MCP enable**: `McpManager` → `ConfigWriter` (the JSON writer preserves unknown
keys; the TOML writer normalizes and warns) after `ConfigBackup`. The lockfile
records the target with `linkMode = config`.

**Doctor**: compares the lockfile against the filesystem across eight finding
kinds — `broken_link`, `missing_target`, `copy_drift`, `orphan_file`,
`agent_path_missing`, `user_shadow`, `store_missing`, `adapter_unknown`. `--fix`
repairs the ones that can be repaired and never touches files the user made.
It is all-or-nothing: `Doctor.run(fix:)` takes no filter, so a caller cannot
repair one finding in isolation.

**Intelligence**: `EffectiveLoadScanner` (globalPath plus compatPaths, including
plugin caches) → `DedupeEngine` (exact = normalized hash; near =
NLContextualEmbedding **mean-centered** cosine ≥ 0.72, because raw cosine is
useless here — the spike proved it) → `QualityScorer` (heuristic plus an
explanation; foundation-model refinement runs async when Apple Intelligence is
available) → `BudgetMeter` (4 bytes per token, ±20%; MCP schema tokens come from
the health cache) → `DescriptionLinter`.

## Safety invariants (enforced by tests)
1. Never overwrite or delete anything AgeOS did not create (lockfile plus an
   xattr/manifest double-check).
2. Client configs are parse-merged only; a malformed file is refused; the
   millisecond-stamped backups can never collide.
3. Scanning is static only — skill content is never executed (booby-trap test).
4. HealthCheck escalates SIGTERM → 2s → SIGKILL, leaving zero orphaned processes
   (verified with pgrep).
5. Every path comparison goes through `canonicalPath` (the /var → /private/var
   trap).

## Concurrency
Swift 6 strict concurrency. Core is `Sendable` structs and value types; the
process and pipe wrappers are `final class @unchecked Sendable` with their own
internal locking (`LineCollector`, `DataBox`). In the app, `AppModel` is
`@MainActor` and heavy work runs through `Task.detached`.

## Presentation layer
The app renders through a token layer rather than ad-hoc values: `Space`,
`Radius`, `Stroke`, an `age`-prefixed type ramp, and ten semantic colors backed
by an Asset Catalog. Each color set declares four appearance variants, so macOS
resolves light, dark and Increase Contrast without any view branching on the
environment.

Five shared components (`StatTile`, `RatioMeter`, `StatusPill`, `SectionCard`,
`FindingRow`) take their data through parameters and never read `AppModel`, which
keeps them previewable and testable in isolation. Copy parameters are typed
`LocalizedStringKey` so the String Catalog can extract them; data parameters take
`String` through explicit `verbatim:` initialisers.

Problem counts on every surface — Overview, Diagnostics, the menu bar — read one
array built by `DiagnosticsBuilder`, so they cannot disagree about the state of
the machine.
