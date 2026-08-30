# AgeOS — System Architecture

## Tổng quan

```
┌─ SwiftUI app (apps/AgeOS) ─┐  ┌─ CLI ageos ─┐  ┌─ ageos-mcp (stdio) ─┐
│  AppModel (@Observable)    │  │ ArgumentPar.│  │ swift-sdk, 9 tools  │
└─────────────┬──────────────┘  └──────┬──────┘  └─────────┬───────────┘
              └────────────── AgeOSCore (SPM lib) ─────────┘
   store/ · skill-model/ · sources/ · lockfile/ · index/ · adapters/
   link-engine/ · doctor/ · mcp/ · config-writers/ · intelligence/
```

**Filesystem là source of truth.** SQLite (`index.sqlite`, GRDB) chỉ là cache — `ageos reindex` rebuild từ FS. Lockfile `ageos.lock.json` nhớ version + nơi đã enable (targets: scope/linkMode/path).

## Layout `~/.ageos/`
```
library/skills/<ns>/<name>/<version>/ + current→   # ns = owner/repo | local/<slug>
library/mcp/<ns>/<name>/<version>/                  # payload .mcpb
adapters/          # user override (id trùng thắng bundled)
backups/<ts-ms>/   # config client trước MỌI lần ghi
adopted/           # skill import từ `ageos adopt --import`
bin/               # ageos + ageos-mcp cài local
index.sqlite · sources.json · ageos.lock.json · mcp-servers.json · cache/
```

## Luồng chính

**Sync**: SourceProvider.fetch (GitHub tarball + ETag/sha, Local content-hash) → SkillScanner (`**/SKILL.md` ≤4 depth) → validate → Store.installVersion (atomic rename) → setCurrent (symlink swap atomic) → LinkEngine.propagateVersionChange (copy targets re-sync, tôn trọng drift) → Index upsert.

**Enable**: AdapterSpec quyết định mode. Symlink → link tới `library/.../current` (swap version lan tự động). Copy → CopySync + `.ageos-manifest.json` (sha256/file) + xattr `dev.ageos.managed`. Preflight: đích tồn tại mà không phải của mình → CHẶN.

**MCP enable**: McpManager → ConfigWriter (Json giữ key lạ; Toml normalize + warn) sau khi ConfigBackup. Lockfile targets linkMode=`config`.

**Doctor**: đối chiếu lockfile ↔ FS (broken link, missing target, copy drift, orphan-marker, user-shadow, agent-path-missing) — `--fix` sửa loại sửa được, không bao giờ đụng đồ user.

**Intelligence**: EffectiveLoadScanner (globalPath + compatPaths, kể cả plugin cache) → DedupeEngine (exact = hash chuẩn hóa; near = NLContextualEmbedding **mean-centered** cosine ≥0.72 — raw cosine vô dụng, spike proof) → QualityScorer (heuristic + explain; FM refine async khi Apple Intelligence bật) → BudgetMeter (4 bytes/token ±20%, MCP schema tokens từ health cache) → DescriptionLinter.

## Bất biến an toàn (test-enforced)
1. Không ghi đè/xóa thứ AgeOS không tạo (lockfile + xattr/manifest double-check).
2. Config client: parse-merge only, refuse file hỏng, backup mili-giây không bao giờ đè nhau.
3. Scan static-only — không execute nội dung skill (booby-trap test).
4. HealthCheck: SIGTERM→2s→SIGKILL, 0 process mồ côi (pgrep test).
5. Mọi so sánh path qua `canonicalPath` (bẫy /var → /private/var).

## Concurrency
Swift 6 strict. Core = struct Sendable + value types; process/pipe wrappers là final class @unchecked Sendable có lock nội bộ (LineCollector, DataBox). App: AppModel @MainActor, việc nặng qua Task.detached.
