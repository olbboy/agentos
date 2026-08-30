# AgeOS — Codebase Summary

## Cây thư mục
```
Package.swift                 # SPM: AgeOSCore lib + ageos + ageos-mcp
Sources/AgeOSCore/
  AgeOSError.swift            # lỗi typed + remedy
  AgeOSHome.swift             # layout ~/.ageos, env AGEOS_HOME (test isolation)
  SyncEngine.swift            # fetch→store→index→propagate orchestrator
  store/        Store (version+current swap), SkillRef, AtomicFile, CanonicalPath
  skill-model/  SkillManifest, SkillParser (Yams+swift-markdown), SkillValidator
  sources/      SourceProvider, GitHubSource (tarball+ETag), LocalSource,
                SourcesRegistry, SkillScanner, TarballExtractor, HTTPClient (mock được),
                SkillsShSource (API đo thật 30/8)
  lockfile/     Lockfile v1 (skills+mcpServers, targets scope/linkMode/path)
  index/        IndexDB (GRDB; migrations v1, v2-mcp-health; rebuild từ FS)
  adapters/     AdapterSpec, AdapterRegistry (bundled specs/ + user override)
                adapters/specs/*.json  ← 6 adapter bundled (root /adapters symlink tới đây)
  link-engine/  LinkEngine (enable/disable/propagate), CopySync (manifest hash), ManagedMarker (xattr)
  doctor/       Doctor (7 loại finding, --fix)
  mcp/          McpServerModel+McpLibrary, McpRegistrySource, McpbImporter,
                HealthCheck (LineCollector/DataBox), McpManager
  config-writers/ ConfigWriter protocol + ConfigBackup, JsonConfigWriter, TomlConfigWriter
  intelligence/ EffectiveLoadScanner (+adopt), DedupeEngine, QualityScorer,
                BudgetMeter, DescriptionLinter, ScanEngine
Sources/AgeOSCLI/             # ageos: source|list|reindex|enable|disable|targets|doctor|
                              #        mcp *|adopt|scan|budget|lint|search (--json khắp nơi)
Sources/AgeOSMCPServer/       # ageos-mcp: 9 tools mapping vào core
Tests/AgeOSCoreTests/         # 68 test / 23 suite; fake-home + fake-agent world; fixtures golden
apps/AgeOS/                   # SwiftUI app (xcodegen project.yml)
  Sources/  AgeOSApp (WindowGroup+MenuBarExtra+Settings), AppModel (@MainActor @Observable),
            FsEventsWatcher, Views/ (Library, TargetMatrix, Budget, Scan, Adopt, Mcp)
  Tests/    AppModelTests (3)   UITests/ smoke (cần TCC automation lần đầu)
spike/                        # throwaway Phase 1: HelloMCP, fm-check, spike-symlink-matrix.sh
scripts/                      # generate-completions.sh, release-lane.sh
plans/260830-0405-ageos-mvp/  # plan + phase status + spike report
```

## Điểm vào đọc-hiểu nhanh
1. `SyncEngine.swift` — mọi luồng gặp nhau ở đây.
2. `LinkEngine.swift` — bất biến an toàn enable/disable.
3. `AdapterSpec.swift` + `adapters/specs/*.json` — mô hình data-driven.
4. `ScanEngine.swift` — pipeline intelligence.

## Con số hiện tại
Core+CLI+MCP: 68 tests xanh (~12s gồm perf 500-skill). App: build xanh + 3 unit tests. Máy thật đã verify: sync anthropics/skills (20 skill), enable claude-code(symlink)+codex(copy), MCP 3-client round-trip byte-sạch, dogfood ageos-mcp (9 tools, ≈458 schema tokens).
