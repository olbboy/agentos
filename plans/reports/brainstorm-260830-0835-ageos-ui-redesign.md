---
type: brainstorm
date: 2026-08-30
slug: ageos-ui-redesign
status: accepted
branch: main
handoff: ak-plan
---

# Redesign UI/UX app AgeOS (macOS)

## Summary

App SwiftUI hiện tại chạy đúng nhưng chưa có lớp thiết kế: 1107 LOC / 11 file, 6 tab phẳng, không token, không component dùng chung, cold-start dẫn người dùng vào màn rỗng. Đã học pattern từ 30 màn thực trên Mobbin (platform `web` — Mobbin **không có** macOS, đây là giới hạn evidence đã biết) và ánh xạ vào 6 vấn đề cụ thể. Chốt hướng B: design system + tái cấu trúc IA, không đụng AgeOSCore.

## Contract

**Outcome.** App AgeOS có lớp thiết kế nhất quán (token + component tái dùng), có màn Overview làm cold-start trả lời được "máy tôi đang ra sao" trong một màn hình, và Diagnostics phân theo mức nghiêm trọng kèm hành động sửa tại chỗ. Chuỗi UI tiếng Anh trên hạ tầng String Catalog.

**Constraints.**
- Không sửa `AgeOSCore` — mọi dữ liệu cần đã có sẵn trong `AppModel` (đã verify: `inventory`, `budgets`, `scanReport`, `doctorFindings`, `lock`, `lastSyncAt`, `mcpServers`, `healthByName`).
- Không đổi hành vi CLI `ageos` và `ageos-mcp`.
- macOS 26+, Swift 6, SwiftUI, `@Observable`. Dựng project qua xcodegen.
- Palette thương hiệu riêng (user chốt) → **phải tự lo dark mode + accessibility**, không thừa hưởng miễn phí từ system.
- `swift test` xanh; UI smoke test cập nhật cùng change.

**Non-goals.**
- Không thêm feature mới (không adapter mới, không Keychain, không lệnh mới).
- Không đụng README / website / docs sản phẩm ngoài `design-guidelines.md`.
- Không đổi format output `--json`.
- Không dịch sang tiếng Việt trong lần này (chỉ dựng hạ tầng để bổ sung sau).

**Acceptance criteria.**
1. `~/.ageos/` rỗng → app mở ra Overview hiển thị inventory quét được từ máy thật + CTA import, **không** phải Library rỗng.
2. `grep` trong `Sources/Views/` không còn literal spacing/font/color rời — tất cả qua token layer.
3. Một màn duy nhất so sánh được budget giữa mọi agent, cùng thang đo, hiện tỉ lệ `used / threshold`.
4. Diagnostics gom theo severity kèm số đếm; mỗi finding có action hoặc ghi rõ "no automatic fix".
5. `doctor --fix` không nằm ở toolbar; là CTA destructive riêng + confirm.
6. Không còn màn nào trộn VI/EN; base `en` trong `Localizable.xcstrings`.
7. `swift test` xanh, UI smoke test pass sau khi cập nhật.
8. `.accessibilityLabel` hiện có được giữ hoặc cải thiện, không regress.
9. `docs/design-guidelines.md` tồn tại, ghi palette + contrast ratio đo được (hệ quả bắt buộc của việc chọn palette riêng).

## Evidence — hiện trạng (đọc source)

| # | Vấn đề | Bằng chứng |
|---|---|---|
| P1 | Không có first-run story | Cold start = Library rỗng + `ContentUnavailableView`. Adopt (quét máy, giá trị demo mạnh nhất) là tab thứ 5 |
| P2 | Không có design system | Spacing ad-hoc rải rác `.padding(4)` / `.padding(.vertical, 2)` / `.padding(.vertical, 3)`; không component dùng chung nào |
| P3 | Không so sánh được cross-agent | `BudgetView` mỗi agent một `GroupBox` + `ProgressView` riêng → không đối chiếu được giữa các agent |
| P4 | Diagnostics không có severity, không remediation | `ScanView` xếp 4 `GroupBox` ngang hàng; lint findings là bullet text, không action |
| P5 | Destructive ngang hàng benign | `Doctor --fix` nằm cạnh `Quét` trong toolbar, cùng trọng số thị giác |
| P6 | Trộn ngôn ngữ | Section name EN (`Library`, `Target Matrix`…) + chuỗi VI (`Quét`, `Chỉ deprecated`, `Đóng`), không cơ chế i18n |

## Evidence — pattern học từ Mobbin (30 màn, platform web)

**Usage / budget** — [Cofounder](https://mobbin.com/screens/e9c05b3d-54e8-44db-9995-15ab9a95078a) · [StackAI](https://mobbin.com/screens/a2976bbf-d4f1-407f-8c56-88779215f037) · [Neon](https://mobbin.com/screens/57e883a3-2c9f-42aa-b776-c873201a6cdc) · [Snowflake](https://mobbin.com/screens/14dc8d20-6643-472e-b933-34b0678b83cc) · [OpenAI Platform](https://mobbin.com/screens/40877c48-2093-4ba7-849d-621a72ed3af2) · [Obvious](https://mobbin.com/screens/7486593b-f8a9-44a0-9959-b113cff27bf2)
- Bất biến: luôn hiện `used / limit`, không bao giờ số trần. AgeOS đang hiện `≈12345 tokens` không mẫu số.
- Neon: dải 4 tile metric gọn ở đầu = "tình trạng máy trong một liếc" — AgeOS thiếu hoàn toàn.
- StackAI: mỗi dòng một meter căn phải, **chung một thang** → so sánh tức thì. Đây là lời giải cho P3.
- Cofounder: receipt itemized kèm "% of period usage" mỗi dòng = đúng hình dạng "top 5 skill ngốn context".

**Integrations / toggle** — [Qatalog](https://mobbin.com/screens/bf24e755-2a66-4aa1-b64b-ad156bbd0641) · [Rox](https://mobbin.com/screens/3e819b97-b78d-4adc-86ea-b100a8e6e9e7) · [MagicPath](https://mobbin.com/screens/d1209570-1bd3-49db-9c89-23bd6aa03f47) · [Gemini](https://mobbin.com/screens/e90f55bd-da8b-4882-b8ab-591857e2b74c)
- Qatalog: dòng đang bật được **tint nền** → đọc trạng thái không cần nhìn switch. Target Matrix hiện là lưới switch mini không màu, liếc không ra.
- Rox: tách nhóm CURRENT vs NOT CONNECTED — gom theo trạng thái hơn hẳn một list phẳng.
- MagicPath: status chip cạnh tên + đúng một action bên phải, rất ít mực.

**Diagnostics** — [Semrush](https://mobbin.com/screens/0f5eb2f2-aa33-4170-998c-0754c86f0b82) · [Vanta](https://mobbin.com/screens/7b3e98c2-b1fd-4c66-b4f4-51fbbb0a346f) · [Supabase](https://mobbin.com/screens/e3ac7f2c-bdd0-42a4-ac13-76fb893fd06d) · [Base44](https://mobbin.com/screens/71d29ab5-bd1b-46a9-a9d7-0932827e94a4) · [HubSpot](https://mobbin.com/screens/e9b536b6-aed8-4e62-b615-bde7c0428fe0)
- Vanta: summary "OK 31 / 28%" vs "Needs attention 77" **trước**, bảng chi tiết sau. AgeOS đổ thẳng 4 GroupBox không tóm tắt.
- Semrush + Supabase: severity là tab/nhóm có viền màu kèm số đếm (Errors / Warnings / Notices).
- Semrush + HubSpot: mỗi issue mang sẵn "How to fix" inline.
- Base44: "Fix with AI" là CTA chính **ở cuối report**, sau danh sách issue — không phải trong toolbar. Lời giải cho P5.
- Supabase: "Rerun linter" + giải thích cách sinh finding đặt ở đáy → chỗ đúng cho disclaimer ±20% của budget.

**Registry / browser** — [Claude Connectors](https://mobbin.com/screens/89caa346-2310-4edc-9439-a36dc843906c) · [GitHub](https://mobbin.com/screens/6ce1e117-4cf7-4193-bc09-2295e7417277) · [Coda](https://mobbin.com/screens/e1d76fca-7fe3-4b0b-810a-bccc2e46fb8f)
- Claude: filter gộp vào dropdown Type/Category thay vì sidebar cố định — đúng khi ít facet.
- GitHub: chip "Recommended" + dòng publisher verified = trust signal. Library của AgeOS hiện **không** hiện nguồn gốc, không hiện quality score (dù core đã tính).

## Options đã cân nhắc

| | A — Chỉ design system | **B — Design system + IA (chọn)** | C — Đại tu + chrome tùy biến |
|---|---|---|---|
| Việc | Token + component, viết lại 6 view, giữ IA | A + màn Overview, gom 6→3 nhóm, severity model | B + borderless window, sidebar tự vẽ, animation |
| Giả định chịu lực | IA hiện tại ổn, chỉ bề mặt yếu | Overview đủ dữ liệu thật để đáng một màn | Có người bảo trì chrome tự vẽ lâu dài |
| Vỡ đầu tiên khi | Mở app vẫn thấy Library rỗng → P1 nguyên vẹn, chỉ đẹp hơn | Overview thành dashboard chết vì việc thật nằm ở Matrix | macOS đổi material/vibrancy, hoặc Reduce Transparency / Increase Contrast phá layout |
| Chi phí bỏ dở | Thấp — component tái dùng dưới mọi IA | Trung bình — IA đụng `ContentView` + ~2 file mới; design system vẫn sống | Cao nhất, khó lùi |

**Giả định của B đã verify**, không phải phỏng đoán: mọi dữ liệu Overview cần đã nằm sẵn trong `AppModel` — không phát sinh việc ở core.
**Giảm thiểu rủi ro của B**: mỗi tile trên Overview phải deep-link + mang CTA riêng, tuyệt đối không phải summary chỉ-đọc.

## Hướng đã chốt

### IA mới
```
Overview            ← MỚI, màn đích khi mở app
Distribute
  ├ Library
  ├ Target Matrix
  └ MCP Servers
Health
  ├ Context Budget
  └ Diagnostics     ← gộp Scan + Doctor
```
**Adopt được hoà tan**, không còn là tab: 4 số thống kê → dải metric của Overview; danh sách duplicate path → nhóm severity trong Diagnostics; nút import → CTA chính lúc cold-start, và giữ là action thường trực trên Overview sau đó.

### Token layer (`Sources/DesignSystem/Tokens.swift`)
- Spacing thang 4pt: `xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32`
- Radius: `sm 6 · md 10 · lg 14`
- Type ramp: display / title / headline / body / callout / caption / mono (mọi con số dùng `monospacedDigit`)
- Vai trò màu ngữ nghĩa: `surface · surfaceRaised · border · textPrimary · textSecondary · accent · success · warning · danger · info`
- **Bắt buộc**: định nghĩa trong Asset Catalog kèm biến thể light + dark (hệ quả của palette riêng)

### Component dùng chung (`Sources/DesignSystem/Components/`)
| Component | Pattern nguồn | Thay thế |
|---|---|---|
| `StatTile` | Neon, Cofounder | `AdoptView.stat()` |
| `RatioMeter` | StackAI | `ProgressView` rời trong BudgetView |
| `StatusPill` | Semrush, MagicPath | Capsule "deprecated", `HealthBadge` |
| `SectionCard` | Vanta, Rox | mọi `GroupBox` trần |
| `FindingRow` | Semrush "How to fix" | bullet text trong ScanView |

### Thay đổi từng màn
- **Overview** — dải 4 `StatTile`; split Healthy / Needs attention (Vanta) deep-link sang Diagnostics; hàng `RatioMeter` mỗi agent chung thang (P3); cold-start hero khi `lock.skills.isEmpty`; footer last-sync + Sync.
- **Diagnostics** — nhóm Error / Warning / Info kèm số đếm; mỗi `FindingRow` có action hoặc ghi rõ không sửa được; CTA destructive "Repair all fixable (N)" ở đáy + confirm (P5); note cách sinh finding + Rerun ở đáy.
- **Target Matrix** — tint nền dòng đang bật (Qatalog); header cột hiện mode symlink/copy + badge verified; thêm meta nguồn + token ước tính vào dòng skill.
- **Library** — filter dropdown (source / deprecated / enabled-anywhere) thay toggle đơn; thêm trust signal: nguồn gốc + token ước tính + badge số agent đang bật.
- **Context Budget** — giữ chi tiết per-agent, chuyển disclaimer ±20% xuống đáy (Supabase).
- **MCP Servers** — tách nhóm Enabled / Available (Rox); `StatusPill` cho health.

### i18n
`Localizable.xcstrings` String Catalog, base `en`. Chuỗi VI hiện có → EN. Xcode tự trích từ literal trong `Text(...)`, không cần quản key tay. Tiếng Việt bổ sung sau như một translation.

## Rủi ro

1. **Palette riêng (user chốt) kéo theo scope bắt buộc** — mất dark mode và accessibility miễn phí của system. Redesign **phải** sinh `docs/design-guidelines.md` kèm contrast ratio đo được, vì repo chưa có brand. Đây là scope phát sinh có thật, không phải tuỳ chọn.
2. **Hoà tan tab Adopt** xoá một mục nav người dùng đã quen.
3. **`AgeOSUISmokeTests` sẽ vỡ** — assert vào static text `"Library"`, `"Target Matrix"`, `"Budget"`. Phạm vi vỡ nhỏ và có kiểm soát: `Budget` → `Context Budget`, thêm assert `Overview`. Chuỗi vẫn tiếng Anh nên không vỡ thêm. `AppModelTests` không chạm view → an toàn.
4. **Overview thành dashboard chết** nếu chỉ để đọc → điều kiện nghiệm thu #1 và mitigation "mỗi tile mang CTA" là để chặn việc này.

## Handoff

→ `ak-plan` với contract trên. Gợi ý phase: (1) token + Asset Catalog + design-guidelines.md, (2) 5 component + unit test, (3) String Catalog + chuyển chuỗi sang EN, (4) Overview + IA restructure + hoà tan Adopt, (5) Diagnostics severity + remediation, (6) 4 màn còn lại, (7) cập nhật UI smoke test + a11y audit.

## Unresolved questions

1. Palette cụ thể chưa chốt (hue accent, thang neutral). Cần một vòng quyết định brand trước phase 1 — brainstorm này chỉ chốt rằng palette là *riêng*, chưa chốt *màu gì*.
2. Ngưỡng cảnh báo budget mỗi agent lấy từ đâu để `RatioMeter` có mẫu số? `BudgetMeter.Report.warnThreshold` là optional — agent nào không có threshold thì meter hiển thị ra sao?
3. Menu bar extra và Settings có nằm trong phạm vi redesign không? Hiện chưa tính vào 7 phase trên.
