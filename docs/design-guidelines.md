# AgeOS Design Guidelines

The design language for the AgeOS SwiftUI app. Every spacing, type, and color
decision in `apps/AgeOS/Sources/` resolves to a token defined here.

This document is written in English to match `README.md`, `CONTRIBUTING.md`,
`SECURITY.md`, and the app itself. Four older documents in `docs/` are in
Vietnamese; translating them is tracked separately and deliberately out of scope
for the UI redesign.

## The governing principle

AgeOS exists to **report state** — budget over threshold, findings by severity,
adapter verified or not. If brand color competes with status color, the signal
gets weaker. So the palette is near-monochrome: neutrals carry the layout, and
saturation is reserved for information.

Three rules follow from that, and they are not negotiable:

1. **The accent is separated in hue from every status color.** Measured below.
2. **The accent never fills a large area.** Active state, a left rule, a small
   data emphasis, an eyebrow. Never a page background or a hero panel.
3. **Color is never the only channel.** Every status that a color communicates is
   also carried by text, an icon, or an accessibility value. Someone who cannot
   distinguish the hues loses nothing.

Brand identity comes from the type ramp, the spacing scale, and layout rhythm —
not from saturation.

## Why an Asset Catalog instead of Swift color constants

An Asset Catalog can declare light, dark, and High Contrast variants under a
single name. macOS picks the right variant for the environment, so no view needs
`@Environment(\.colorScheme)` or a check for Increase Contrast. Choosing a custom
palette normally means giving up that machinery; declaring it in the catalog
keeps it.

Every color set ships **four variants**, the product of two independent axes:

| `appearances` in `Contents.json` | Environment |
|---|---|
| *(absent)* | Light, normal contrast |
| `luminosity: dark` | Dark, normal contrast |
| `contrast: high` | Light, **Increase Contrast on** |
| `luminosity: dark` + `contrast: high` | Dark, Increase Contrast on |

Verified, not assumed: `actool` compiles the catalog for the macOS deployment
setting with exit 0, and the resulting `Assets.car` contains 40 entries —
10 names x 4 variants.

## Spacing and radius

`apps/AgeOS/Sources/DesignSystem/Spacing.swift`. A 4pt scale; every gap in the
app is one of these values.

| Token | Value | Typical use |
|---|---|---|
| `Space.xs` | 4 | Icon-to-label inside a control |
| `Space.sm` | 8 | Between related controls |
| `Space.md` | 12 | Row padding |
| `Space.lg` | 16 | Card padding |
| `Space.xl` | 24 | Between sections |
| `Space.xxl` | 32 | Screen margins |
| `Radius.sm` | 6 | Pills, small controls |
| `Radius.md` | 10 | Cards |
| `Radius.lg` | 14 | Large containers |
| `Stroke.hairline` | 1 | Dividers, card borders |
| `Stroke.emphasis` | 2 | Selected state, left rules |

## Typography

`apps/AgeOS/Sources/DesignSystem/Typography.swift`. Every token is prefixed
`age` — `Font.body` and `Font.callout` already exist in SwiftUI, and shadowing
them would silently override system Dynamic Type behavior.

| Token | Size | Weight | Use |
|---|---|---|---|
| `Font.ageDisplayL` | 28 | semibold | The single largest number on a screen |
| `Font.ageTitleL` | 20 | semibold | Screen title |
| `Font.ageHeadline` | 15 | medium | Section and card headers |
| `Font.ageBody` | 13 | regular | Body copy |
| `Font.ageCallout` | 12 | regular | Supporting copy |
| `Font.ageCaption` | 11 | regular | Metadata, footnotes |
| `Font.ageNumeric` | 15 | medium, monospaced digits | Any number that changes |
| `Font.ageNumericS` | 12 | regular, monospaced digits | Secondary numbers in a row |

Monospaced digits matter more than they look: without them, a column of numbers
shifts horizontally whenever a value changes — very visible on a meter that
updates while you watch it.

## Palette

`apps/AgeOS/Sources/DesignSystem/Palette.swift` maps semantic names to the
catalog. Names describe **role**, not color: changing the hue of `statusDanger`
later means editing the catalog, not auditing call sites.

### Hex values

| Token | Light | Dark | Light + HC | Dark + HC |
|---|---|---|---|---|
| `surface` | `#FBFBFD` | `#101015` | `#FFFFFF` | `#000000` |
| `surfaceRaised` | `#FFFFFF` | `#1A1A21` | `#FFFFFF` | `#0E0E13` |
| `borderSubtle` | `#D5D5DE` | `#35353F` | `#6A6A78` | `#8A8A99` |
| `textPrimary` | `#16161C` | `#F3F3F7` | `#000000` | `#FFFFFF` |
| `textSecondary` | `#5A5A6A` | `#A8A8B8` | `#35353F` | `#D2D2DE` |
| `accentBrand` | `#4A41C4` | `#A79EFF` | `#2E23A8` | `#C3BCFF` |
| `statusSuccess` | `#10703C` | `#4FCB84` | `#075229` | `#7FE3A8` |
| `statusWarning` | `#8A5300` | `#E8B24C` | `#5E3900` | `#F5CC7A` |
| `statusDanger` | `#B3251C` | `#FF8F84` | `#8C1810` | `#FFB3AC` |
| `statusInfo` | `#0A5DB8` | `#74B4F2` | `#063F7E` | `#A3CEFA` |

### Measured contrast against the surface it sits on

| Token | Light | Dark | Light + HC | Dark + HC | Minimum | Verdict |
|---|---|---|---|---|---|---|
| `borderSubtle` | 1.41:1 | 1.56:1 | 5.32:1 | 6.18:1 | 3.0:1 | PASS (decorative in normal contrast — see note) |
| `textPrimary` | 17.43:1 | 17.14:1 | 21.00:1 | 21.00:1 | 4.5:1 | PASS |
| `textSecondary` | 6.54:1 | 8.09:1 | 12.12:1 | 14.01:1 | 4.5:1 | PASS |
| `accentBrand` | 7.14:1 | 8.11:1 | 10.93:1 | 11.96:1 | 4.5:1 | PASS |
| `statusSuccess` | 5.97:1 | 9.22:1 | 9.34:1 | 13.46:1 | 4.5:1 | PASS |
| `statusWarning` | 6.12:1 | 9.85:1 | 10.19:1 | 13.80:1 | 4.5:1 | PASS |
| `statusDanger` | 6.35:1 | 8.59:1 | 9.32:1 | 12.30:1 | 4.5:1 | PASS |
| `statusInfo` | 6.21:1 | 8.63:1 | 10.40:1 | 12.77:1 | 4.5:1 | PASS |

### Contrast on raised surfaces (cards)

| Token | Light | Dark | Light + HC | Dark + HC |
|---|---|---|---|---|
| `textPrimary` | 18.02:1 | 15.63:1 | 21.00:1 | 19.25:1 |
| `textSecondary` | 6.76:1 | 7.38:1 | 12.12:1 | 12.85:1 |
| `accentBrand` | 7.38:1 | 7.40:1 | 10.93:1 | 10.96:1 |
| `statusSuccess` | 6.17:1 | 8.41:1 | 9.34:1 | 12.33:1 |
| `statusWarning` | 6.33:1 | 8.98:1 | 10.19:1 | 12.65:1 |
| `statusDanger` | 6.57:1 | 7.84:1 | 9.32:1 | 11.27:1 |
| `statusInfo` | 6.42:1 | 7.87:1 | 10.40:1 | 11.70:1 |

### Accent hue separation

| Compared with | Light | Dark | Light + HC | Dark + HC | Minimum |
|---|---|---|---|---|---|
| `statusSuccess` | 96.6° | 99.9° | 97.8° | 101.7° | 60° |
| `statusWarning` | 152.0° | 153.7° | 151.4° | 153.7° | 60° |
| `statusDanger` | 119.5° | 119.8° | 118.9° | 118.8° | 60° |

All ratios are computed with the WCAG 2.1 relative-luminance formula
(gamma-decode each channel, weight 0.2126 / 0.7152 / 0.0722, then
`(L1 + 0.05) / (L2 + 0.05)`), not estimated by eye.

**About `borderSubtle`.** In normal contrast it measures 1.41:1 (light) and
1.56:1 (dark), below the 3:1 floor for UI components. That is deliberate. WCAG
1.4.11 exempts purely decorative elements, and a divider that actually hits 3:1
on white is roughly `#949494` — a heavy rule that would break the near-monochrome
direction. `borderSubtle` separates regions; it never carries state. Under
Increase Contrast it rises to 5.32:1 and 6.18:1, where the user has asked for
stronger edges.

**Why the accent sits at hue 244-246 degrees.** It has to stay clear of green,
amber, and red so it never reads as a status. Indigo does that with the smallest
gap at 96.6 degrees, and it is close enough to the macOS system indigo to sit
comfortably next to window chrome.

## Usage rules

- **Accent** — active navigation item, selection rule, small data emphasis,
  eyebrow labels. Not backgrounds, not large fills.
- **Status colors** — text, icons, meter fills, pill foregrounds. Never a
  full-width background: at that size the hue dominates the screen and stops
  reading as a specific signal.
- **Never color alone** — pair every status color with a label, an icon, or an
  `.accessibilityValue`. Row tints, meters, and pills all follow this.
- **No `.opacity()` on text** — it silently breaks the measured ratios above. Use
  `textSecondary`, which is already measured.
- **No literals** — no raw `.padding(12)`, `.font(.system(size:))`, or
  `Color(red:green:blue:)` in a view. This is enforced by grep in the UI phases.

## Verification

The Asset Catalog is compiled with `xcrun actool` against the macOS deployment
setting declared in `apps/AgeOS/project.yml`; it must exit 0.

Views are checked for leaked design literals:

```bash
grep -rE '\.padding\([0-9]|\.font\(\.system|Color\(red:' apps/AgeOS/Sources/Views/
```

### Runtime accessibility audit

`testAccessibilityAuditAcrossAllScreens` in `apps/AgeOS/UITests/` runs
`performAccessibilityAudit()` across all six screens. By default that runs every
audit type the platform supports — on macOS: `.contrast`,
`.sufficientElementDescription`, `.elementDetection`, `.hitRegion`, `.action`,
and `.parentChild`. Each issue it finds becomes an `XCTIssue`, so the test fails
on its own without hand-written assertions.

**It needs Accessibility permission to run.** XCUITest inspects another process's
UI, which macOS gates behind TCC. Without that grant the test harness sees no
windows at all and every UI test fails with "no matches found" — including the
smoke test that predates this document. Grant Accessibility (System Settings →
Privacy & Security → Accessibility) to whichever program launches the tests —
Xcode when running from the IDE, or your terminal when running `xcodebuild`.

The automated audit does not replace listening with VoiceOver. It catches missing
labels and insufficient contrast; it cannot tell that a label reads "Button" or
that the reading order makes no sense. Those need a person.
