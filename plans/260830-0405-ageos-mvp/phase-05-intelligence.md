---
phase: 5
title: "Phase 5: Intelligence"
status: done
priority: P1
effort: "5d"
dependencies: [3, 4]
---

# Phase 5: Intelligence

## Overview
Lớp khác biệt cạnh tranh: Adopt (quét hiện trạng rải rác), effective-load map, dedupe exact+near, deprecated, quality score + phân loại, Context Budget Meter, description linter, nguồn skills.sh.

## Requirements
- Functional: `ageos adopt [--import]` (inventory mọi skill/MCP đang cài ở mọi agent + plugin cache → effective-load map: agent nào load gì, trùng từ path nào); `ageos scan` (exact-dupe SHA-256 normalized; near-dupe cosine NLContextualEmbedding ≥0.90 trên name+description+200 dòng đầu; deprecated: repo archived / frontmatter `deprecated` / registry status); quality score 0-100 heuristic + phân loại taxonomy; `ageos budget [--target]`; `ageos lint <skill>`; search skills.sh index (install-count làm quality signal).
- Non-functional: TUYỆT ĐỐI không execute code trong skill khi scan (static only); embedding/phân loại on-device (FoundationModels khi khả dụng, fallback keyword — không gọi API ngoài); scan 500 skills <30s trên M-series.

## Architecture
- `EffectiveLoadScanner`: dùng AdapterRegistry liệt kê mọi path load (kể cả `~/.claude/plugins` cache, `~/.agents/skills`) → map {agent → [skill@path]} → nhóm trùng.
- `DedupeEngine`: hash normalize (trim whitespace, sort frontmatter) cho exact; NLContextualEmbedding + cosine cho near; cache vector trong Index.
- `QualityScorer`: trọng số metadata đầy đủ, description lint pass, có `references/`/`scripts/`, upstream stars/freshness/license, install-count skills.sh; classification qua FoundationModels prompt cố định (fallback: keyword map).
- `BudgetMeter`: cost skill = tokens(name+description) luôn-tải per agent catalog; cost MCP = schema tokens từ HealthCheck; hệ số từ spike; ngưỡng cảnh báo per agent (vd nguy cơ silent-drop, cap 40 tools kiểu Cursor) khai báo trong adapter JSON.
- `DescriptionLinter`: độ dài, trigger words mơ hồ, trùng lặp với skill khác (từ DedupeEngine).

## Related Code Files
- Create: `Sources/AgeOSCore/intelligence/**` (EffectiveLoadScanner, DedupeEngine, QualityScorer, BudgetMeter, DescriptionLinter), `Sources/AgeOSCore/sources/SkillsShSource.swift`, CLI subcommands, `Tests/**` (fixtures có dupe/deprecated cài sẵn)
- Modify: `Index` (bảng vectors, scores, effective_load)

## Implementation Steps
1. EffectiveLoadScanner + `adopt` (inventory → report; `--import` copy vào library, giữ nguồn `local/adopted`).
2. DedupeEngine exact → near (đo threshold trên fixtures thật lấy từ awesome-lists, chỉnh 0.85-0.95).
3. Deprecated detector (GitHub archived qua source metadata, frontmatter, registry).
4. QualityScorer + classification (FoundationModels availability check + fallback; kết quả kèm `explain` từng tiêu chí).
5. BudgetMeter + ngưỡng per-adapter; output bảng + `--json`.
6. DescriptionLinter.
7. SkillsShSource (search + install count; graceful khi API đổi).
8. Perf test 500 skills; snapshot tests cho scorer (chống drift điểm ngẫu nhiên).

## Todo
- [x] adopt + effective-load map (+ --import vào nguồn local/adopted) — máy thật: 169 skill distinct, 345 load entries, 147 skill ≥2 agent
- [x] Dedupe exact (hash chuẩn hóa whitespace/lowercase) + near (NLContextualEmbedding MEAN-CENTERED — spike chứng minh raw cosine vô dụng; threshold 0.72 calibrate trên fixture: paraphrase bắt được, khác nghĩa không false-positive) — máy thật: 18 cặp exact (bộ Cloudflare cài 3 nơi)
- [x] Deprecated detector (index archived + frontmatter; test archived→deprecated pass)
- [x] Quality score 0-100 + explain từng tiêu chí + classification keyword (FM refine async khi Apple Intelligence bật — máy dev tắt nên keyword là đường chính, UI ghi "heuristic mode"); snapshot test khóa 87 điểm
- [x] Budget Meter + ngưỡng adapter + đọc read-only config MCP — máy thật: claude-code ≈9,992 tokens/136 skills, cảnh báo 6 MCP chưa đo schema
- [x] Description linter (5 rule; 48 finding trên máy thật)
- [x] skills.sh source (schema API đo thật 30/8: /api/search?q= → {skills:[{id,name,installs,source}]}; degrade im lặng)
- [x] Perf 500 skills = 11.3s (<30s) + snapshot tests + test bẫy-execute chứng minh static-only

## Success Criteria
- [x] Fixture 1 skill / 3 path / 2 agent → map chỉ đúng cả 3 + cross-agent view (unit test pass)
- [x] Cặp near-dupe bị bắt ở 0.72 post-centering; cặp khác nghĩa (pg-replication vs image-marketing) không false-positive
- [x] Repo archived → deprecated (unit); `ageos budget --target claude-code` = 9,992 tokens — đối chiếu /context thủ công ghi trong output CLI (nested claude -p bị chặn OAuth, xem spike report)
- [x] Scan static-only: test booby-trap (script tự ghi marker nếu bị chạy) — marker vắng sau toàn pipeline

## Risk Assessment
- NLContextualEmbedding chất lượng kém trên description ngắn → signal: false-positive/negative trên fixture; response: đổi input (name+desc+body head), hạ/nâng threshold, fallback model2vec.swift (đã chọn dự phòng).
- FoundationModels bị tắt (user không bật Apple Intelligence) → signal: availability != available; response: fallback keyword classifier, UI ghi rõ "heuristic mode".
- skills.sh API không ổn định → signal: schema đổi/4xx; response: source này optional, degrade im lặng + note trong doctor.
- Hệ số token lệch model → đã chấp nhận ±20%, ghi rõ trong UI là ước lượng.
