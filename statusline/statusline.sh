#!/bin/bash
# fable-mode statusline renderer for Claude Code.
# Receives session JSON on stdin, prints one ANSI-colored line.
# Installed to ~/.claude/fable-mode/statusline.sh (stable path) by scripts/install-statusline.sh;
# session_start.sh re-syncs the copy so plugin updates propagate.
set -u
INPUT="$(cat)"

HOOK_INPUT="$INPUT" python3 - <<'PY' 2>/dev/null || printf 'fable-mode'
import json, os, subprocess

d = json.loads(os.environ["HOOK_INPUT"])
model = (d.get("model") or {}).get("display_name") or "?"
cost = d.get("cost") or {}
cwd = (d.get("workspace") or {}).get("current_dir") or "."
sid = d.get("session_id", "")
tp = d.get("transcript_path")

DATA = os.path.expanduser("~/.claude/fable-mode")
CTX_LIMIT = int(os.environ.get("FABLE_CTX_LIMIT", "200000"))

# ANSI helpers
DIM, RST = "\033[2m", "\033[0m"
def c(code, s): return f"\033[{code}m{s}{RST}"
SEP = f" {DIM}│{RST} "

# level pin
level = "auto"
try:
    lv = open(f"{DATA}/level").read().strip()
    if lv in ("lite", "full", "deep"):
        level = lv
except Exception:
    pass

# context used = usage of the last assistant message in the transcript (tail read only)
ctx = None
try:
    size = os.path.getsize(tp)
    with open(tp, "rb") as fh:
        fh.seek(max(0, size - 131072))
        tail = fh.read().decode("utf-8", "ignore").splitlines()
    for line in reversed(tail):
        try:
            rec = json.loads(line)
        except Exception:
            continue
        if rec.get("type") == "assistant":
            u = (rec.get("message") or {}).get("usage") or {}
            if u:
                ctx = (u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0)
                       + u.get("cache_creation_input_tokens", 0))
                break
except Exception:
    pass

# session totals from the fable-mode stats log (kept fresh by the Stop hook)
out_tok = None
try:
    for line in open(f"{DATA}/stats.jsonl"):
        try:
            r = json.loads(line)
        except Exception:
            continue
        if r.get("session") == sid:
            out_tok = r.get("out")
except Exception:
    pass

# git branch (fast, silent)
branch = ""
try:
    branch = subprocess.run(["git", "-C", cwd, "branch", "--show-current"],
                            capture_output=True, text=True, timeout=1).stdout.strip()
except Exception:
    pass

def k(n):
    return f"{n / 1000:.1f}k" if n < 1_000_000 else f"{n / 1_000_000:.2f}M"

parts = [c("35;1", "⚡ fable") + " " + c("36", level), c("35", model)]
if branch:
    parts.append(c("34", f"⎇ {branch}"))
if ctx is not None:
    pct = min(100, round(100 * ctx / CTX_LIMIT))
    filled = min(10, pct // 10)
    color = "32" if pct < 60 else ("33" if pct < 85 else "31")
    bar = c(color, "█" * filled) + c("2", "░" * (10 - filled))
    parts.append(f"ctx {bar} {c(color, f'{pct}%')} {DIM}· {k(max(0, CTX_LIMIT - ctx))} left{RST}")
if out_tok is not None:
    parts.append(f"{DIM}out{RST} {c('36', k(out_tok))}")
usd = cost.get("total_cost_usd")
mins = (cost.get("total_duration_ms") or 0) // 60000
money = f"{c('33', f'${usd:.2f}')} {DIM}· {mins}m{RST}" if usd is not None else (f"{DIM}{mins}m{RST}" if mins else "")
if money:
    parts.append(money)
la, lr = cost.get("total_lines_added"), cost.get("total_lines_removed")
if la or lr:
    parts.append(c("32", f"+{la or 0}") + c("31", f"/−{lr or 0}"))

print(SEP.join(parts))
PY
