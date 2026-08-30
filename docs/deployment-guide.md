# AgeOS — Deployment Guide

## Local install (dev)
```bash
swift build -c release
mkdir -p ~/.ageos/bin && cp .build/release/ageos .build/release/ageos-mcp ~/.ageos/bin/
export PATH="$HOME/.ageos/bin:$PATH"        # thêm vào shell rc
./scripts/generate-completions.sh            # zsh/bash/fish completions
```
App: `cd apps/AgeOS && xcodegen generate && xcodebuild -scheme AgeOS -configuration Release build` → `.app` trong DerivedData (hoặc dùng release lane bên dưới).

## Test
```bash
swift test                                   # 68 tests, không đụng $HOME thật
cd apps/AgeOS && xcodebuild -scheme AgeOS test   # unit app; xem note TCC bên dưới
```
TCC bootstrap (1 lần, persistent — chạy test từ automation/agent harness):
1. **Developer Tools** cho app chịu trách nhiệm của tiến trình gọi xcodebuild (chạy từ
   Claude Code desktop = `/Applications/Claude.app`; từ Terminal = Terminal.app) —
   thiếu quyền này AgeOSTests hang 120s rồi timeout (kTCCServiceDeveloperTool silent-deny,
   không popup). Mở đúng pane: `open "x-apple.systempreferences:com.apple.preference.security?Privacy_DeveloperTool"`
2. **Automation** — gate THỨ HAI sẽ hỏi khi chạy AgeOSUITests lần đầu (interactive approve).

## CI (GitHub Actions)
- `ci.yml`: push/PR → `swift build && swift test` + app build (macOS 26 image; nếu GitHub chưa có → đổi `runs-on` sang image mới nhất có Xcode 26, job app tách khỏi required checks).
- `release.yml`: tag `v*` → chạy release lane, upload artifacts + checksums lên GitHub Release.

## Release lane (`scripts/release-lane.sh`)
1. `swift build -c release` → tarball `ageos-cli-<ver>-arm64.tar.gz` (ageos + ageos-mcp + completions).
2. `xcodebuild -scheme AgeOS -configuration Release` → `AgeOS.app` → zip.
3. **Ký + notarize CHỈ KHI có env**: `AGEOS_SIGN_IDENTITY` (Developer ID Application) + `AGEOS_NOTARY_PROFILE` (notarytool keychain profile). Thiếu → phát hành **unsigned** kèm hướng dẫn:
   ```bash
   xattr -dr com.apple.quarantine AgeOS.app   # hoặc ageos binary
   ```
4. SHA-256 checksums cho mọi artifact.
Sparkle appcast: HOÃN tới khi có Developer ID (Sparkle yêu cầu ký) — không block v0.1.0.

## Homebrew cask
Cask tại `packaging/homebrew/ageos.rb`, đã publish lên `olbboy/homebrew-tap`. Học từ cài thật 30/8/2026 (Homebrew 2026 + macOS 26):
```bash
brew trust olbboy/tap        # BẮT BUỘC: tap bên thứ ba phải trust trước (Tap-Trust mới)
brew tap olbboy/tap
brew install --cask ageos    # cờ --no-quarantine đã bị Homebrew gỡ bỏ
# nếu Gatekeeper chặn khi mở (macOS 26 bỏ xattr -r):
find /Applications/AgeOS.app -exec xattr -d com.apple.quarantine {} \; 2>/dev/null
```

## Publish checklist (cần quyết định user — CHƯA làm)
1. Chốt GitHub owner + đổi bundle id placeholder `io.github.owner.ageos` (apps/AgeOS/project.yml, cask).
2. `git remote add origin … && git push` (repo public) — chạy secret-scan trước khi public.
3. Tạo tap repo + đẩy cask.
4. Tag `v0.1.0` → release workflow chạy.
5. (Tùy chọn, $99/năm) Apple Developer ID → thêm secrets ký/notarize → bật Sparkle.
