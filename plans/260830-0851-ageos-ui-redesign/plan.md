---
title: "AgeOS UI redesign — design system + tái cấu trúc IA"
description: "Dựng token layer + 5 component dùng chung cho app SwiftUI, thêm màn Overview làm cold-start, gom 6 tab thành 3 nhóm, Diagnostics phân theo severity kèm remediation, và chuyển toàn bộ chuỗi (app + core) sang tiếng Anh trên String Catalog."
status: completed
priority: P1
effort: "9.5d"
tags: [ageos, macos, swiftui, design-system, ia, i18n]
created: 2026-08-30
---

# AgeOS UI redesign

## Overview

App AgeOS chạy đúng nhưng chưa có lớp thiết kế: 1107 LOC / 11 file SwiftUI, 6 tab phẳng, không token, không component dùng chung, mở app lần đầu rơi vào màn rỗng. Plan này dựng design system, tái cấu trúc IA quanh một màn Overview, và thống nhất ngôn ngữ toàn sản phẩm sang tiếng Anh.

Contract gốc: [`../reports/brainstorm-260830-0835-ageos-ui-redesign.md`](../reports/brainstorm-260830-0835-ageos-ui-redesign.md) — hướng B (design system + IA), palette thương hiệu riêng, base `en` + String Catalog.

**Hai quyết định chốt trong lúc lập plan, khác với brainstorm:**

1. **Dịch cả `AgeOSCore` sang tiếng Anh** (Phase 3). Brainstorm đặt non-goal "không sửa AgeOSCore", nhưng verify cho thấy core phát ~81 chuỗi tiếng Việt **hiển thị thẳng lên UI**: 60 `AgeOSError` (message + remedy) → `ErrorBanner`, ~9 `Doctor.Finding.message` → `FindingRow`, 3 `BudgetMeter.Report.warnings`, ~8 lint/deprecated reason. Đổi app sang tiếng Anh mà giữ core tiếng Việt sẽ **tệ hơn hiện trạng**. Non-goal cũ bị thay thế có ý thức; ranh giới mới: sửa **chuỗi** trong core, không sửa **hành vi** hay **shape** của core.
2. **MenuBarExtra + SettingsView vào phạm vi** (Phase 8). Nếu bỏ ngoài, hai bề mặt này giữ chuỗi tiếng Việt cũ trong khi phần còn lại đã sang tiếng Anh.

## Goals

| # | Goal | Priority |
|---|------|----------|
| 1 | Có token layer + Asset Catalog light/dark; không còn literal spacing/font/color rời trong view | P1 |
| 2 | 5 component dùng chung thay thế toàn bộ code UI ad-hoc | P1 |
| 3 | Cold-start mở ra Overview có dữ liệu thật + CTA, không phải Library rỗng | P1 |
| 4 | So sánh được budget giữa mọi agent trên một màn, chung thang đo | P1 |
| 5 | Diagnostics gom theo severity, mỗi finding có action hoặc ghi rõ không sửa được | P1 |
| 6 | Hành động destructive (`doctor --fix`) tách khỏi toolbar | P2 |
| 7 | Toàn sản phẩm (app + core + CLI) nói tiếng Anh, trên hạ tầng String Catalog | P1 |
| 8 | `docs/design-guidelines.md` (tiếng Anh) tồn tại, ghi palette + contrast ratio đo được | P2 |

## Phases

| # | Phase | Status |
|---|-------|--------|
| 1 | [Phase 1: Design Tokens](./phase-01-design-tokens.md) | Done |
| 2 | [Phase 2: Shared Components](./phase-02-shared-components.md) | Done |
| 3 | [Phase 3: Core Strings English](./phase-03-core-strings-english.md) | Done |
| 4 | [Phase 4: App String Catalog](./phase-04-app-string-catalog.md) | Done |
| 5 | [Phase 5: Overview And IA](./phase-05-overview-and-ia.md) | Done |
| 6 | [Phase 6: Diagnostics Severity](./phase-06-diagnostics-severity.md) | Done |
| 7 | [Phase 7: Remaining Screens](./phase-07-remaining-screens.md) | Done |
| 8 | [Phase 8: MenuBar And Settings](./phase-08-menubar-and-settings.md) | Done |
| 9 | [Phase 9: Tests And Accessibility](./phase-09-tests-and-accessibility.md) | Done |

Thứ tự phụ thuộc:

```
1 (tokens) ─┐
            ├─> 2 (components) ─┐
3 (core EN) ─> 4 (app EN) ──────┼─> 5 (Overview+IA) ─┐
                                ├─> 6 (Diagnostics) ─┤
                                ├─> 7 (4 màn còn lại)├─> 9 (tests + a11y)
                                └─> 8 (menubar+settings)┘
```

Phase 1 và 3 độc lập, chạy song song được. Phase 5–8 độc lập với nhau sau khi 2 và 4 xong.

## Constraints

- Không đổi **hành vi** hay **shape** của `AgeOSCore` — Phase 3 chỉ đổi nội dung chuỗi, giữ nguyên `AgeOSError.Code`, tên field, cấu trúc `--json`.
- Ngoại lệ có kiểm soát duy nhất về API: đổi `BudgetMeter.skillTokens` từ internal sang `public` (Phase 2) để Library hiện token ước tính mà không nhân bản công thức.
- macOS 26+, Swift 6, SwiftUI, `@Observable`. Không thêm dependency mới.
- Palette riêng → **tự lo** dark mode, Increase Contrast, Reduce Transparency. Không thừa hưởng miễn phí từ system.
- Mọi thay đổi phải giữ `swift test` xanh; test nào assert chuỗi tiếng Việt thì cập nhật cùng phase gây vỡ.

## Non-goals

- Không thêm feature mới: không adapter mới, không Keychain, không lệnh CLI mới.
- Không dịch sang tiếng Việt trong lần này — chỉ dựng hạ tầng để bổ sung sau.
- Không đụng README / CONTRIBUTING / SECURITY / website, và **không dịch 4 file tiếng Việt sẵn có trong `docs/`** (quyết định validate session 1 — nợ kỹ thuật có sẵn, đáng một plan riêng).
- Không đổi format hay schema output `--json`.
- Không đại tu chrome cửa sổ (borderless, sidebar tự vẽ) — đã loại ở brainstorm.

## Success Criteria

- [~] `~/.ageos/` rỗng → app mở ra Overview + CTA import — **code + test đã có, chưa chạy được**: XCUITest thiếu quyền Accessibility trên máy này (xem Session 3)
- [x] `grep -rE '\.padding\([0-9]|\.font\(\.system|Color\(red:' apps/AgeOS/Sources/Views/` trả về rỗng
- [x] Một màn duy nhất so sánh budget mọi agent, chung thang, hiện tỉ lệ `used / threshold`
- [x] Diagnostics gom Error / Warning / Info kèm số đếm; mỗi row có action hoặc nhãn "No automatic fix"
- [x] `doctor --fix` không truy cập được từ toolbar; là CTA destructive riêng + confirm dialog
- [x] Grep tiếng Việt trong `Sources/` + `apps/AgeOS/Sources/` chỉ còn khớp trong comment. Ngoại lệ có chủ ý duy nhất: `DescriptionLinter.swift:45` giữ `"khi nào"`, `"dùng khi"` — đó là **pattern dò trigger**, không phải chuỗi hiển thị; xoá sẽ đổi *hành vi* linter với skill mô tả bằng tiếng Việt, vi phạm ràng buộc "không đổi hành vi core"
- [x] `Localizable.xcstrings` tồn tại, base `en`, phủ mọi chuỗi UI của app
- [x] `swift test` xanh (69 core + 22 app). [~] UI smoke test đã cập nhật cho IA mới nhưng **chưa chạy được** — thiếu quyền Accessibility
- [x] Mọi `.accessibilityLabel` được giữ hoặc cải thiện (22 label + 11 value; mọi Button không có text hiển thị đều có nhãn). [~] Audit VoiceOver/tự động **chưa chạy** — thiếu quyền Accessibility
- [x] `docs/design-guidelines.md` tồn tại, **viết bằng tiếng Anh**, ghi palette + contrast ratio đo được cho cả light và dark
- [x] 4 file tiếng Việt sẵn có trong `docs/` không bị sửa
- [~] App render ở 4 chế độ — **chưa kiểm chứng bằng mắt**: máy từ chối Screen Recording nên không chụp được màn hình. Token đã khai báo đủ 4 biến thể và `actool` biên dịch sạch

## Validation Log

### Session 1 — 2026-08-30

#### Verification Results

- **Tier:** Full (9 phases → cả 4 role)
- **Claims checked:** 35
- **Verified:** 34 | **Failed:** 1 | **Unverified:** 0
- **Failed còn tồn đọng: 0** — claim vỡ duy nhất đã được sửa ngay trong session này (xem mục Failures). Plan đủ điều kiện triển khai.

**Flow Tracer — claim chịu lực của Phase 5 (cold-start có dữ liệu thật): VERIFIED.**
Đường đi `AppModel.start()` → `refreshAll()` → `run { … }`:
`SyncEngine.init` gọi `home.ensureLayout()` dùng `createDirectory(withIntermediateDirectories: true)` → **tạo** thư mục, không throw trên home trắng (`AgeOSHome.swift:30-34`). `Lockfile.load` trả `Lockfile()` rỗng khi thiếu file, không throw (`Lockfile.swift:65-68`). `AdapterRegistry.init` nạp 6 spec **bundled** qua `Bundle.module` (`AdapterRegistry.swift:47`, `Package.swift:29` `resources: [.copy("adapters/specs")]`) — `~/.ageos/adapters/` chỉ override. `EffectiveLoadScanner.scan()` đọc thư mục agent thật, độc lập với `~/.ageos`.
→ Trên `AGEOS_HOME` trắng, `inventory` **vẫn được điền bằng dữ liệu máy thật**. Tiền đề Phase 5 đứng vững.

**Contract Verifier:**
- `skillTokens` — `static func` ở `BudgetMeter.swift:37` có đúng **1** caller (`BudgetMeter.swift:56`). 3 tham chiếu trong test trỏ vào `Report.skillTokens` **property** (đã public), không phải func. Trùng tên → đã ghi cảnh báo phân biệt vào Phase 2.
- `AdoptView` — **3** tham chiếu: `AgeOSApp.swift:68`, chính file, và `runAdopt` trong `AppModel.swift:143` (giữ lại). Phase 5 phủ hết, không sót caller.

**Scope Auditor:**
- `AppModel` có 4 nơi khởi tạo: 1 trong app (`AgeOSApp.swift:6`, `@State`), 3 trong test. Instance-scoped — thêm cache token hay computed property là an toàn.
- **Finding:** `Lockfile.SkillEntry.targets` dùng key `<adapterId>@global` **hoặc** `<adapterId>@<projectPath>`, nên một adapter chiếm được nhiều entry. Phase 7 ghi "đếm từ targets" là mơ hồ, `targets.count` sẽ đếm thừa → đã sửa thành đếm adapterId phân biệt.

**Fact Checker:** 11 file app, `Doctor.Kind` 8 case, 6 adapter đều có `catalogTokensWarn` (10000–20000), `AgeOSApp.swift` 165 dòng, 20 assertion test khớp chuỗi tiếng Việt, `QualityScorer.Input` cần `ParsedSkill`, `openWindow` đã import nhưng chưa dùng — tất cả VERIFIED.
Bổ sung: **không** có script/CI/README nào grep prose output của CLI (`scripts/` chỉ có `release-lane.sh` và `generate-completions.sh`) → rủi ro #2 của Phase 3 hạ xuống mức thấp.

#### Failures

1. **[Flow Tracer] Phase 6 — nút "Repair" per-row không triển khai được.** `Doctor.run(fix: Bool)` (`Sources/AgeOSCore/doctor/Doctor.swift:38`) là all-or-nothing, không nhận filter. Phase 6 ghi mỗi finding `fixable` sẽ có nút Repair "giới hạn ở finding đó" — không có API nào làm được. → Đã sửa: bỏ per-row repair, chỉ giữ một CTA toàn cục.

#### Decisions

| # | Câu hỏi | Quyết định | Ảnh hưởng |
|---|---|---|---|
| 1 | Xử lý claim FAILED về per-row repair | Bỏ nút per-row, chỉ giữ CTA toàn cục | Phase 6: bảng action viết lại, thêm cột `StatusPill`; chỉ "Disable everywhere" cho deprecated là action đổi trạng thái ở cấp row |
| 2 | Hướng palette | Gần đơn sắc — màu **dành riêng để tải thông tin trạng thái**; nhận diện đến từ type + spacing | Phase 1: thêm ràng buộc accent phải tách hue khỏi 3 status color, không làm nền lớn, không là kênh truyền tin duy nhất |
| 3 | Ngôn ngữ `docs/design-guidelines.md` (phát hiện: 4 file `docs/` đang tiếng Việt, README/CONTRIBUTING/SECURITY tiếng Anh) | Tiếng Anh; không đụng 4 file cũ | Phase 1: ghi rõ ngôn ngữ + non-goal không sửa docs cũ. `docs/` tạm trộn — nợ kỹ thuật có sẵn, không do plan này sinh ra |

#### Whole-Plan Consistency Sweep

- Files reread: `plan.md`, `phase-01` … `phase-09` (10 file)
- Decision deltas checked: 3
- Reconciled stale references: 5 (Phase 1 ×4, Phase 2 ×1, Phase 6 ×5, Phase 7 ×1)
- Unresolved contradictions: 0

### Session 2 — 2026-08-30 · kiểm chứng thực nghiệm tooling Apple

Session 1 xác minh plan **so với repo**. Session 2 xác minh plan **so với hành vi thật của Xcode/xcodegen**, bằng cách chạy lệnh chứ không đọc tài liệu. Tài liệu nói sai một chỗ quan trọng.

| # | Claim | Verdict | Bằng chứng (chạy được, không phải trích dẫn) |
|---|---|---|---|
| 1 | **Phase 4**: String Catalog tự trích chuỗi, không cần đụng `project.yml` | **REFUTED** | `xcodebuild -showBuildSettings` → `SWIFT_EMIT_LOC_STRINGS = NO`, `LOCALIZATION_PREFERS_STRING_CATALOGS = NO`. Tài liệu ghi "enabled by default" — đúng với **template project Xcode**, sai với project do xcodegen sinh |
| 2 | **Phase 1**: `.xcassets` dưới `Sources/` tự vào resource, không cần sửa `project.yml` | **CONFIRMED** | `xcodegen generate` → `project.pbxproj` chứa `Assets.xcassets in Resources` trong `PBXResourcesBuildPhase` |
| 3 | **Phase 1**: Asset Catalog hỗ trợ biến thể High Contrast | **CONFIRMED + nâng cấp** | `actool --platform macosx --minimum-deployment-target 26.0` biên dịch thành công colorset **4 biến thể** (Any / Dark / HC / Dark+HC), exit 0 → plan sửa từ 2 lên 4 biến thể |
| 4 | **Phase 9**: chỉ có cách rà accessibility bằng tay | **REFUTED (có lợi)** | SDK macOS: `performAccessibilityAudit` `API_AVAILABLE(macos(14.0))`; target là 26.0. 6 loại audit trên macOS, trong đó `.contrast` và `.sufficientElementDescription` phủ đúng 2 tiêu chí đang định làm tay |
| 5 | xcodegen có set cấu hình ngôn ngữ | **CONFIRMED** | `developmentRegion = en`, `knownRegions = (Base, en)` — không cần đụng |
| 6 | **Phase 2/6**: khung test nào cho file test mới | **RESOLVED** | `Testing.framework` có trong platform macOS của Xcode, cùng chỗ `XCTest.framework` → swift-testing chạy được trong bundle xcodegen. Chốt: unit test mới dùng swift-testing (khớp 15 file core), UI test giữ XCTest (bắt buộc, `XCUIApplication` là API họ XCTest) |

**Thay đổi đã áp:**
- Phase 4: thêm **bước 0 làm cổng chặn** — bật 2 setting trong `project.yml` rồi xác minh bằng lệnh trước khi làm gì khác; `project.yml` chuyển từ *Verify* sang **Modify**; thêm tiêu chí đếm số key trong catalog > 0.
- Phase 1: 4 biến thể mỗi color set thay vì 2; ghi nhận `.xcassets` không cần sửa `project.yml`.
- Phase 9: thêm `testAccessibilityAuditAcrossAllScreens` chạy trên 6 màn; rà tay VoiceOver đổi vai từ *chính* thành *bổ sung*, tập trung vào thứ máy không bắt được (nhãn vô nghĩa, thứ tự đọc).
- Phase 2 + 6: chốt swift-testing cho unit test mới, XCTest cho UI test.

**Công cụ đã cân nhắc:**
- [`pointfreeco/swift-snapshot-testing`](https://github.com/pointfreeco/swift-snapshot-testing) (4325⭐, push 2026-08-24) — hỗ trợ macOS + SwiftUI. **Chưa đưa vào plan**: thêm dependency vào app target và snapshot test dễ gãy theo phiên bản OS. Đáng cân nhắc nếu muốn khoá regression thị giác cho design system — quyết định của bạn, không phải mặc định của tôi.
- [`liamnichols/xcstrings-tool`](https://github.com/liamnichols/xcstrings-tool) (370⭐, push 2025-08-12) — **loại**. Nó sinh hằng Swift type-safe từ `.xcstrings` để tránh gõ sai key; nhưng plan dùng `Text("literal")` nơi literal **chính là** key, nên không có rủi ro gõ sai để mà tránh. Thêm vào chỉ là dùng công cụ cho có.

**Ghi chú về grok CLI:** đã chạy 3 lần ở chế độ headless (`-p` / `--prompt-file`, `--output-format plain`, giới hạn tool read-only, max-turns 40/120/25). Cả 3 lần chỉ in ra phần dẫn nhập, không ra kết luận nào — không dùng được để xác minh. Mọi phát hiện ở bảng trên đến từ chạy lệnh trực tiếp, bằng chứng mạnh hơn ý kiến của bất kỳ model nào.

### Session 3 — 2026-08-30 · kiểm chứng lúc triển khai

Session 1 xác minh plan so với repo, Session 2 so với tooling Apple. Session 3 là
những gì **chỉ lộ ra khi thật sự chạy code**. Hai claim của plan bị bác bỏ.

| # | Claim | Verdict | Bằng chứng |
|---|---|---|---|
| 1 | **Phase 4**: bật 2 build setting là catalog tự được điền | **REFUTED** | Cả hai setting `= YES` (đã đo), `.stringsdata` sinh ra đủ 19 file — nhưng `Localizable.xcstrings` vẫn 0 key. Việc gộp ngược vào file nguồn là hành vi của **Xcode IDE**, không phải `xcodebuild`. Đường CLI: `xcrun xcstringstool sync`. Đã đóng gói thành `scripts/sync-string-catalog.sh` |
| 2 | **Phase 8**: `openWindow` không mở lại được cửa sổ thì *đặt id cho WindowGroup* | **REFUTED** | Đặt id → app khởi động không mở cửa sổ nào (0/2 lần chạy thấy Window). `defaultLaunchBehavior(.presented)` biên dịch được nhưng không cứu. Đã đổi sang đường reopen của AppKit (`applicationShouldHandleReopen`), giữ `WindowGroup` không id |
| 3 | **Phase 3**: grep theo dấu tiếng Việt đủ để chứng minh sạch | **REFUTED** | Bỏ sót chuỗi tiếng Việt **không dấu** (`"Command cho server manual (vd: npx)."`). Tầng dò thứ hai theo từ vựng tìm thêm 8 dòng |
| 4 | **Phase 3**: khối lượng ~81 chuỗi | **SAI SỐ 3.7×** | Thực tế 309 dòng (core 159 · CLI 136 · MCP 7 · test 3 + 4 bổ sung). 81 đúng với phần hiển thị lên app; Phase 3 còn phủ prose CLI |
| 5 | **Phase 9**: `AgeOSUISmokeTests` hiện tại pass, chỉ cần cập nhật | **REFUTED** | Chạy UI test **gốc tại HEAD** trong worktree sạch → cũng fail y hệt. Không phải regression: máy này thiếu quyền Accessibility nên XCUITest không thấy window nào |
| 6 | **Phase 3**: 20 assertion test khớp chuỗi tiếng Việt sẽ vỡ | **3, không phải 20** | Chỉ 3 assertion thật sự so khớp nội dung core. 17 dòng còn lại là *thông điệp lỗi* tiếng Việt của test, không tham gia so khớp |
| 7 | **Phase 6**: dựng fixture test bằng init của struct core | **KHÔNG DÙNG ĐƯỢC** | `public struct` Swift không tự có memberwise init public. Thêm init vào core sẽ mở rộng API surface, vi phạm ràng buộc "ngoại lệ API duy nhất". Đã dựng fixture bằng decode JSON — tiện thể khoá luôn hình dạng `--json` |

#### Chưa chứng minh được (giới hạn môi trường, không phải giới hạn code)

Máy này có phiên GUI (`launchctl managername` = Aqua, console user = `leo`) nhưng
process chạy lệnh **không được cấp quyền TCC**:

- `screencapture` → `could not create image from display` (thiếu Screen Recording)
- XCUITest → `app.windows.count == 0` trên mọi cấu hình (thiếu Accessibility)

Hệ quả: 3 UI test đã viết đúng (`testLaunchShowsSidebar`,
`testColdStartLandsOnOverview`, `testAccessibilityAuditAcrossAllScreens`) nhưng
chưa chạy được ở đây. **Cách chạy:** cấp quyền Accessibility cho Xcode (chạy từ
IDE) hoặc cho terminal (chạy `xcodebuild`), rồi:

```bash
cd apps/AgeOS && xcodebuild test -project AgeOS.xcodeproj -scheme AgeOS \
  -destination 'platform=macOS,arch=arm64' -only-testing:AgeOSUITests
```

Bằng chứng gián tiếp app vẫn mở cửa sổ bình thường ngoài môi trường test: prefs
`io.github.olbboy.ageos` chứa `NSWindow Frame …ContentView…-1-AppWindow-1 =
"25 461 900 612"` — frame 900×612 khớp `minWidth: 900` của `ContentView`, và chỉ
được app tự ghi ra khi cửa sổ thật sự tồn tại.

#### Ngoại lệ có chủ ý

`Sources/AgeOSCore/intelligence/DescriptionLinter.swift:45` giữ nguyên `"khi nào"`,
`"dùng khi"`. Đó là **pattern dò trigger** trong description, không phải chuỗi
hiển thị. Xoá chúng sẽ đổi *hành vi* của linter với skill mô tả bằng tiếng Việt —
vi phạm ràng buộc "Phase 3 chỉ đổi nội dung chuỗi, không đổi hành vi core".

## Open Questions

1. ~~Hue accent chưa chốt~~ → **Hướng đã chốt** (validate session 1): gần đơn sắc, màu dành riêng cho trạng thái. Còn lại: chốt **giá trị** hex cụ thể trong hướng đó ở bước 1 của Phase 1. Không mở lại hướng.
2. **Có giữ song song bản dịch tiếng Việt cho CLI không?** Phase 3 chuyển CLI sang tiếng Anh. Nếu sau này muốn CLI đa ngôn ngữ thì cần cơ chế riêng (core hiện không có i18n) — ngoài phạm vi plan này.
3. **4 file tiếng Việt trong `docs/` có dịch sang tiếng Anh không?** Đã quyết định *không* trong plan này (giữ phạm vi redesign UI). Là nợ kỹ thuật có sẵn, đáng mở một plan riêng nếu muốn `docs/` nhất quán với README.

<!-- slug: ageos-ui-redesign -->
