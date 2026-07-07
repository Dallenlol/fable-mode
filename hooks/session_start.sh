#!/bin/bash
# Injects the fable-mode operating style into context at session start.
# Single source of truth is the skill file; strip its YAML frontmatter and print the body.
set -euo pipefail

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
DATA_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/fable-mode}"

echo "FABLE MODE ACTIVE — apply the following operating style for the entire session:"
awk 'f; /^---$/ { if (++c == 2) f = 1 }' "$ROOT/skills/fable-mode/SKILL.md"

# Keep the installed statusline copy in sync with the plugin version (no-op if not installed).
if [ -f "$DATA_DIR/statusline.sh" ] && [ -f "$ROOT/statusline/statusline.sh" ]; then
  cp -f "$ROOT/statusline/statusline.sh" "$DATA_DIR/statusline.sh" 2>/dev/null || true
  chmod +x "$DATA_DIR/statusline.sh" 2>/dev/null || true
fi

# Optional persistent level pin: echo lite|full|deep > "$DATA_DIR/level"
if [ -f "$DATA_DIR/level" ]; then
  LEVEL="$(tr -cd 'a-z' < "$DATA_DIR/level")"
  case "$LEVEL" in
    lite|full|deep) echo "" ; echo "User-pinned fable-mode level: $LEVEL — honor it until the user changes it." ;;
  esac
fi
