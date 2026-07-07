#!/bin/bash
# Logs per-session token usage to the plugin data dir. Local only — nothing leaves the machine.
# Fires on Stop; upserts one JSON line per session in stats.jsonl. Always exits 0, prints nothing.
set -u

INPUT="$(cat)"
DATA_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/fable-mode}"
mkdir -p "$DATA_DIR" 2>/dev/null || exit 0

HOOK_INPUT="$INPUT" STATS_FILE="$DATA_DIR/stats.jsonl" python3 - <<'PY' 2>/dev/null || true
import json, os, time

inp = json.loads(os.environ["HOOK_INPUT"])
tp, sid = inp.get("transcript_path"), inp.get("session_id", "unknown")
if not tp or not os.path.exists(tp):
    raise SystemExit

tot = {"turns": 0, "out": 0, "in": 0, "cache_read": 0, "cache_create": 0}
for line in open(tp):
    try:
        rec = json.loads(line)
    except Exception:
        continue
    if rec.get("type") != "assistant":
        continue
    u = (rec.get("message") or {}).get("usage") or {}
    if not u:
        continue
    tot["turns"] += 1
    tot["out"] += u.get("output_tokens", 0)
    tot["in"] += u.get("input_tokens", 0)
    tot["cache_read"] += u.get("cache_read_input_tokens", 0)
    tot["cache_create"] += u.get("cache_creation_input_tokens", 0)

sf = os.environ["STATS_FILE"]
rows = []
if os.path.exists(sf):
    for line in open(sf):
        try:
            if json.loads(line).get("session") != sid:
                rows.append(line.rstrip("\n"))
        except Exception:
            pass
rows.append(json.dumps({"session": sid, "ts": int(time.time()), **tot}))
tmp = sf + ".tmp"
with open(tmp, "w") as fh:
    fh.write("\n".join(rows) + "\n")
os.replace(tmp, sf)
PY
exit 0
