#!/bin/bash
# Regenerates AGENTS.md from the canonical skill. Run after editing skills/fable-mode/SKILL.md.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
{
  echo "<!-- Generated from skills/fable-mode/SKILL.md by scripts/build-agents-md.sh — edit the skill, not this file. -->"
  echo "<!-- Drop this file into any repo root (or your agent's global instructions dir) to apply the fable-mode operating style in AGENTS.md-aware tools: Cursor, Codex, Zed, and others. -->"
  awk 'f; /^---$/ { if (++c == 2) f = 1 }' "$ROOT/skills/fable-mode/SKILL.md"
} > "$ROOT/AGENTS.md"
echo "AGENTS.md regenerated"
