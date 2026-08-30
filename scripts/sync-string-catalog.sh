#!/usr/bin/env bash
# Đồng bộ apps/AgeOS/Sources/Localizable.xcstrings với chuỗi thật trong code.
#
# Vì sao cần script này: Xcode IDE tự gộp chuỗi trích được vào .xcstrings sau mỗi
# lần build. `xcodebuild` từ terminal thì KHÔNG — nó chỉ sinh ra .stringsdata trong
# thư mục build. Không có bước sync này, catalog nằm im ở trạng thái cũ và sai lệch
# âm thầm (không lỗi, không cảnh báo).
#
# Điều kiện: project.yml phải bật SWIFT_EMIT_LOC_STRINGS và
# LOCALIZATION_PREFERS_STRING_CATALOGS — nếu tắt thì không có .stringsdata nào cả.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/apps/AgeOS"
CATALOG="$APP_DIR/Sources/Localizable.xcstrings"
CONFIG="${1:-Debug}"

[ -f "$CATALOG" ] || { echo "Không thấy catalog: $CATALOG" >&2; exit 1; }

echo "==> Build $CONFIG (sinh .stringsdata)"
xcodebuild -project "$APP_DIR/AgeOS.xcodeproj" -scheme AgeOS \
           -configuration "$CONFIG" build >/dev/null

# Chỉ lấy .stringsdata của app target. AgeOSCore và metadata App Shortcuts
# không đóng góp chuỗi UI nào, đưa vào chỉ làm nhiễu catalog.
echo "==> Thu thập .stringsdata"
# while-read thay vì mapfile: macOS ship bash 3.2, không có mapfile.
ARGS=()
COUNT=0
while IFS= read -r f; do
    ARGS+=(--stringsdata "$f")
    COUNT=$((COUNT + 1))
done < <(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path "*AgeOS-*" -path "*$CONFIG*" \
    -path "*/AgeOS.[b]uild/Objects-normal/*" -name "*.stringsdata" 2>/dev/null)

[ "$COUNT" -gt 0 ] || { echo "Không tìm thấy .stringsdata — hai build setting đã bật chưa?" >&2; exit 1; }
echo "    $COUNT file"

echo "==> Sync vào catalog"
xcrun xcstringstool sync "$CATALOG" "${ARGS[@]}"

KEYS=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["strings"]))' "$CATALOG")
echo "==> $KEYS key trong catalog"
[ "$KEYS" -gt 0 ] || { echo "Catalog rỗng — nghĩa là cơ chế trích chuỗi không chạy." >&2; exit 1; }
