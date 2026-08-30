#!/usr/bin/env bash
# AgeOS spike — tái lập các probe xác minh discovery/symlink per agent (throwaway).
# An toàn: chỉ tạo artefact prefix ageos-spike-* và tự dọn; không sửa config nào.
# Usage: ./spike-symlink-matrix.sh [workdir]
set -euo pipefail

WORK="${1:-$(mktemp -d /tmp/ageos-spike.XXXXXX)}"
PROJ="$WORK/proj"
mkdir -p "$PROJ/.agents/skills/ageos-spike-hello" "$WORK/src/ageos-spike-symdir" "$PROJ/.agents/skills/ageos-spike-filelink"

mk_skill() { # $1=path $2=name $3=marker
  cat > "$1" <<EOF
---
name: $2
description: AgeOS spike probe $3 — unique marker for discovery detection.
---
# probe
EOF
}

mk_skill "$PROJ/.agents/skills/ageos-spike-hello/SKILL.md" ageos-spike-hello zx7q
mk_skill "$WORK/src/ageos-spike-symdir/SKILL.md" ageos-spike-symdir vk9r
mk_skill "$WORK/src/filelink-SKILL.md" ageos-spike-filelink qm3w
ln -sf "$WORK/src/filelink-SKILL.md" "$PROJ/.agents/skills/ageos-spike-filelink/SKILL.md"

echo "== grok: project .agents/skills + file-symlink =="
if command -v grok >/dev/null; then
  (cd "$PROJ" && grok inspect --json 2>/dev/null \
    | jq -r '.skills[] | select(.name|startswith("ageos-spike")) | "grok sees: \(.name) [\(.source.type)]"') || true
else echo "grok: not installed"; fi

echo "== codex: project .agents/skills + file-symlink (expect: filelink KHÔNG xuất hiện) =="
if command -v codex >/dev/null; then
  (cd "$PROJ" && codex debug prompt-input "hi" 2>/dev/null | grep -o 'ageos-spike-[a-z]*' | sort -u | sed 's/^/codex sees: /') || true

  echo "== codex: global folder-symlink trong ~/.codex/skills (tạo → đo → xóa) =="
  ln -s "$WORK/src/ageos-spike-symdir" "$HOME/.codex/skills/ageos-spike-symdir"
  trap 'rm -f "$HOME/.codex/skills/ageos-spike-symdir"' EXIT
  (cd /tmp && codex debug prompt-input "hi" 2>/dev/null | grep -o 'ageos-spike-symdir' | head -1 \
    | sed 's/^/codex global folder-symlink DISCOVERED: /') || echo "codex global folder-symlink: NOT FOUND"
  rm -f "$HOME/.codex/skills/ageos-spike-symdir"; trap - EXIT
else echo "codex: not installed"; fi

echo "== claude-code: bằng chứng tự nhiên (symlink có sẵn đang được load) =="
ls -la "$HOME/.claude/skills" 2>/dev/null | grep -c ' -> ' | sed 's/^/symlink dang hoat dong trong ~\/.claude\/skills: /' || true

echo "== antigravity: bằng chứng filesystem (không có CLI để verify discovery) =="
ls -la "$HOME/.gemini/config/skills" 2>/dev/null || echo "~/.gemini/config/skills: missing"

rm -rf "$WORK"
echo "cleanup OK: $WORK removed"
