#!/usr/bin/env bash
# Release lane AgeOS: build CLI + app, ký/notarize NẾU có credential, zip + checksums.
# Usage: ./scripts/release-lane.sh v0.1.0
set -euo pipefail

VERSION="${1:?Usage: release-lane.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
rm -rf "$DIST" && mkdir -p "$DIST"

echo "== 1/4 CLI (release) =="
cd "$ROOT"
swift build -c release
CLI_STAGE="$DIST/ageos-cli-$VERSION-arm64"
mkdir -p "$CLI_STAGE"
cp .build/release/ageos .build/release/ageos-mcp "$CLI_STAGE/"
./scripts/generate-completions.sh "$CLI_STAGE/ageos" "$CLI_STAGE/completions" >/dev/null

echo "== 2/4 App =="
cd "$ROOT/apps/AgeOS"
command -v xcodegen >/dev/null || { echo "cần xcodegen (brew install xcodegen)"; exit 1; }
xcodegen generate
DD="$ROOT/.build/app-dd"
xcodebuild -project AgeOS.xcodeproj -scheme AgeOS -configuration Release \
  -derivedDataPath "$DD" CODE_SIGN_IDENTITY=- build | tail -1
APP="$DD/Build/Products/Release/AgeOS.app"
[ -d "$APP" ] || { echo "Không thấy AgeOS.app"; exit 1; }

echo "== 3/4 Ký + notarize (nếu có credential) =="
if [ -n "${AGEOS_SIGN_IDENTITY:-}" ]; then
  codesign --force --deep --options runtime --sign "$AGEOS_SIGN_IDENTITY" "$APP"
  codesign --force --options runtime --sign "$AGEOS_SIGN_IDENTITY" "$CLI_STAGE/ageos" "$CLI_STAGE/ageos-mcp"
  if [ -n "${AGEOS_NOTARY_PROFILE:-}" ]; then
    NOTARY_ZIP="$DIST/notary-upload.zip"
    ditto -c -k --keepParent "$APP" "$NOTARY_ZIP"
    xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$AGEOS_NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$NOTARY_ZIP"
  fi
else
  cat >"$CLI_STAGE/README-UNSIGNED.txt" <<'EOF'
Ban unsigned (chua co Developer ID). Sau khi tai ve, go quarantine
(macOS 26 da bo co -r cua xattr):
  find AgeOS.app -exec xattr -d com.apple.quarantine {} \; 2>/dev/null
  xattr -d com.apple.quarantine ageos ageos-mcp
EOF
  echo "  (bỏ qua — không có AGEOS_SIGN_IDENTITY; phát hành unsigned + note quarantine)"
fi

echo "== 4/4 Đóng gói + checksums =="
cd "$DIST"
tar -czf "ageos-cli-$VERSION-arm64.tar.gz" -C "$CLI_STAGE/.." "$(basename "$CLI_STAGE")"
ditto -c -k --keepParent "$APP" "AgeOS-$VERSION.zip"
rm -rf "$CLI_STAGE"
shasum -a 256 ./*.tar.gz ./*.zip > checksums.txt
cat checksums.txt
echo "✓ dist/ sẵn sàng cho GitHub Release"
