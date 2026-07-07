#!/bin/bash
# Injects the fable-mode operating style into context at session start.
# Single source of truth is the skill file; strip its YAML frontmatter and print the body.
set -euo pipefail

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

echo "FABLE MODE ACTIVE — apply the following operating style for the entire session:"
awk 'f; /^---$/ { if (++c == 2) f = 1 }' "$ROOT/skills/fable-mode/SKILL.md"
