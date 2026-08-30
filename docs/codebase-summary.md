# AgeOS — Codebase Summary

## Directory tree
```
Package.swift                 # SPM: AgeOSCore lib + ageos + ageos-mcp
Sources/AgeOSCore/
  AgeOSError.swift            # typed errors carrying a remedy
  AgeOSHome.swift             # ~/.ageos layout, AGEOS_HOME env (test isolation)
  SyncEngine.swift            # fetch→store→index→propagate orchestrator
  store/        Store (version + current swap), SkillRef, AtomicFile, CanonicalPath
  skill-model/  SkillManifest, SkillParser (Yams + swift-markdown), SkillValidator
  sources/      SourceProvider, GitHubSource (tarball + ETag), LocalSource,
                SourcesRegistry, SkillScanner, TarballExtractor, HTTPClient (mockable),
                SkillsShSource
  lockfile/     Lockfile v1 (skills + mcpServers; targets carry scope/linkMode/path)
  index/        IndexDB (GRDB; rebuilt from the filesystem by `ageos reindex`)
  adapters/     AdapterSpec, AdapterRegistry (bundled specs/ + user override)
                adapters/specs/*.json  ← 6 bundled adapters (root /adapters symlinks here)
  link-engine/  LinkEngine (enable/disable/propagate), CopySync (manifest hash), ManagedMarker (xattr)
  doctor/       Doctor (8 finding kinds, --fix)
  mcp/          McpServerModel + McpLibrary, McpRegistrySource, McpbImporter,
                HealthCheck (LineCollector/DataBox), McpManager
  config-writers/ ConfigWriter protocol + ConfigBackup, JsonConfigWriter, TomlConfigWriter
  intelligence/ EffectiveLoadScanner (+adopt), DedupeEngine, QualityScorer,
                BudgetMeter, DescriptionLinter, ScanEngine
Sources/AgeOSCLI/             # ageos: source|list|reindex|enable|disable|targets|doctor|
                              #        mcp *|adopt|scan|budget|lint|search (--json everywhere)
Sources/AgeOSMCPServer/       # ageos-mcp: 9 tools mapped onto core
Tests/AgeOSCoreTests/         # 69 tests / 23 suites; fake home + fake agent world; golden fixtures
apps/AgeOS/                   # SwiftUI app (xcodegen project.yml)
  Sources/  AgeOSApp (WindowGroup + MenuBarExtra + Settings), AppModel (@MainActor @Observable),
            FsEventsWatcher,
            DesignSystem/ (Spacing, Typography, Palette, 5 shared components),
            Assets.xcassets/ (10 color sets × 4 appearance variants),
            Localizable.xcstrings (String Catalog, base en),
            Views/ (Overview, Library, TargetMatrix, Mcp, Budget, Diagnostics,
                    DiagnosticSeverity, MenuBar, Settings)
  Tests/    DesignSystemTests + DiagnosticSeverityTests (24, swift-testing)
            AppModelTests (3, XCTest)
  UITests/  smoke, cold start, accessibility audit (needs TCC Accessibility)
spike/                        # throwaway Phase 1: HelloMCP, fm-check, spike-symlink-matrix.sh
scripts/                      # generate-completions.sh, release-lane.sh, sync-string-catalog.sh
plans/                        # plan + phase status per effort
```

## Fast entry points
1. `SyncEngine.swift` — every flow meets here.
2. `LinkEngine.swift` — the enable/disable safety invariants.
3. `AdapterSpec.swift` + `adapters/specs/*.json` — the data-driven model.
4. `ScanEngine.swift` — the intelligence pipeline.
5. `DiagnosticsBuilder` in `Views/DiagnosticSeverity.swift` — the single source
   every app surface counts problems from.

## Current numbers
Core + CLI + MCP: 69 tests green (~13s, including the 500-skill performance
test). App: 24 swift-testing tests plus 3 XCTest, build green.

Verified on a real machine: sync of anthropics/skills (20 skills), enable on
claude-code (symlink) and codex (copy), an MCP three-client round trip that came
back byte-clean, and dogfooding ageos-mcp (9 tools, roughly 458 schema tokens).

The UI tests are written but need Accessibility permission for whatever launches
them; without it XCUITest cannot enter automation mode and all of them fail.
