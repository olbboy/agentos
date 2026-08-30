#!/usr/bin/env bash
# Sinh shell completions cho `ageos` (swift-argument-parser có sẵn generator).
# Usage: ./scripts/generate-completions.sh [path-to-ageos-binary] [output-dir]
set -euo pipefail

BIN="${1:-$HOME/.ageos/bin/ageos}"
OUT="${2:-completions}"

if [ ! -x "$BIN" ]; then
  echo "Không tìm thấy binary ageos tại $BIN" >&2
  echo "Build trước: swift build -c release && cp .build/release/ageos ~/.ageos/bin/" >&2
  exit 1
fi

mkdir -p "$OUT"
"$BIN" --generate-completion-script zsh  > "$OUT/_ageos"
"$BIN" --generate-completion-script bash > "$OUT/ageos.bash"
"$BIN" --generate-completion-script fish > "$OUT/ageos.fish"

echo "✓ Completions tại $OUT/"
echo "  zsh : cp $OUT/_ageos ~/.zsh/completions/ (thêm dir vào fpath)"
echo "  bash: source $OUT/ageos.bash trong ~/.bashrc"
echo "  fish: cp $OUT/ageos.fish ~/.config/fish/completions/"
