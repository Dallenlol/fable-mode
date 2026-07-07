#!/bin/bash
# Installs the fable-mode statusline: copies the renderer to a stable path and
# points ~/.claude/settings.json at it. Refuses to overwrite a different
# statusline unless --force is given.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA="$HOME/.claude/fable-mode"
SETTINGS="$HOME/.claude/settings.json"
TARGET="$DATA/statusline.sh"

mkdir -p "$DATA"
cp -f "$ROOT/statusline/statusline.sh" "$TARGET"
chmod +x "$TARGET"

FORCE="${1:-}" TARGET="$TARGET" SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os, sys

settings_path = os.environ["SETTINGS"]
target = os.environ["TARGET"]
force = os.environ.get("FORCE") == "--force"

settings = {}
if os.path.exists(settings_path):
    settings = json.load(open(settings_path))

existing = settings.get("statusLine", {}).get("command", "")
if existing and target not in existing and not force:
    print(f"A different statusline is configured:\n  {existing}\n"
          f"Re-run with --force to replace it, or keep your current one — "
          f"the fable renderer stays available at {target}")
    sys.exit(0)

settings["statusLine"] = {"type": "command", "command": target}
if os.path.exists(settings_path):
    import shutil
    shutil.copy2(settings_path, settings_path + ".bak")
tmp = settings_path + ".tmp"
json.dump(settings, open(tmp, "w"), indent=2)
os.replace(tmp, settings_path)
print(f"fable-mode statusline installed → {target}\nRestart Claude Code (or start a new session) to see it.")
PY
