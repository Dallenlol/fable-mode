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

# State loop (toggle: /fable-mode:fable-state on|off). Injects the project memory
# file so a /clear'd session resumes from ~2k tokens instead of the full history.
if [ -f "$DATA_DIR/state-loop" ]; then
  echo ""
  if [ -f ".fable-state.md" ]; then
    echo "PROJECT STATE LOOP ACTIVE — .fable-state.md is your continuation context (the chat may have been cleared; trust this file):"
    echo '---'
    head -c 12000 .fable-state.md
    echo ""
    echo '---'
  else
    echo "PROJECT STATE LOOP ACTIVE — no .fable-state.md in this project yet; create it at the end of your first substantive turn."
  fi
  cat <<'RULES'
State-loop discipline: at the end of every substantive turn, create or update .fable-state.md in the project root — goal, key decisions with reasons, what's done, what's next, key file paths — in the simplest form that lets a fresh session continue perfectly. Rewrite for density rather than appending; keep it under ~150 lines. When the context window passes ~60%, tell the user one line: "/clear when ready — .fable-state.md carries the thread."
RULES
fi
