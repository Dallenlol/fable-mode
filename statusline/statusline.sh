#!/bin/bash
# Fable statusline renderer for Claude Code.
# Receives session JSON on stdin, prints a two-line ANSI HUD:
#   line 1: persona/level, model, branch, cost, duration, lines changed
#   line 2: context-window meter + usage-limit meters (5h / 7d, Pro/Max plans)
# Installed to ~/.claude/fable-mode/statusline.sh by scripts/install-statusline.sh;
# session_start.sh re-syncs the copy so plugin updates propagate.
set -u
INPUT="$(cat)"

HOOK_INPUT="$INPUT" python3 - <<'PY' 2>/dev/null || printf 'fable'
import json, os, subprocess, time

d = json.loads(os.environ["HOOK_INPUT"])
model = (d.get("model") or {}).get("display_name") or "?"
cost = d.get("cost") or {}
cwd = (d.get("workspace") or {}).get("current_dir") or "."
sid = d.get("session_id", "")
tp = d.get("transcript_path")
cw = d.get("context_window") or {}
rl = d.get("rate_limits") or {}

DATA = os.path.expanduser("~/.claude/fable-mode")
DIM, RST = "\033[2m", "\033[0m"
def c(code, s): return f"\033[{code}m{s}{RST}"
SEP = f" {DIM}│{RST} "

def meter(pct, width=10, warn=50, crit=80):
    pct = max(0, min(100, round(pct)))
    color = "32" if pct < warn else ("33" if pct < crit else "31")
    filled = min(width, pct * width // 100)
    return c(color, "█" * filled) + c("2", "░" * (width - filled)), c(color, f"{pct}%")

def k(n):
    return f"{n / 1000:.1f}k" if n < 1_000_000 else f"{n / 1_000_000:.2f}M"

# level pin
level = "auto"
try:
    lv = open(f"{DATA}/level").read().strip()
    if lv in ("lite", "full", "deep"):
        level = lv
except Exception:
    pass

# git branch (fast, silent)
branch = ""
try:
    branch = subprocess.run(["git", "-C", cwd, "branch", "--show-current"],
                            capture_output=True, text=True, timeout=1).stdout.strip()
except Exception:
    pass

# session cumulative output tokens (from the fable-mode stats log)
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

# ---- line 1: identity ----
state_loop = os.path.exists(f"{DATA}/state-loop")
has_state = state_loop and os.path.exists(os.path.join(cwd, ".fable-state.md"))
l1 = [c("35;1", "⚡ Fable") + " " + c("36", level), c("35", model)]
if state_loop:
    l1.append(c("32", "✎ state") if has_state else f"{DIM}✎ state ∅{RST}")
if branch:
    l1.append(c("34", f"⎇ {branch}"))
if out_tok is not None:
    l1.append(f"{DIM}out{RST} {c('36', k(out_tok))}")
usd = cost.get("total_cost_usd")
mins = (cost.get("total_duration_ms") or 0) // 60000
if usd is not None:
    l1.append(f"{c('33', f'${usd:.2f}')} {DIM}· {mins}m{RST}")
elif mins:
    l1.append(f"{DIM}{mins}m{RST}")
la, lr = cost.get("total_lines_added"), cost.get("total_lines_removed")
if la or lr:
    l1.append(c("32", f"+{la or 0}") + c("31", f"/−{lr or 0}"))

# ---- line 2: context + usage limits ----
l2 = []

# context: official fields first, transcript-tail fallback for older versions
ctx_pct, ctx_left = cw.get("used_percentage"), None
size = int(os.environ.get("FABLE_CTX_LIMIT", 0)) or cw.get("context_window_size") or 200000
if ctx_pct is None and tp:
    try:
        fsize = os.path.getsize(tp)
        with open(tp, "rb") as fh:
            fh.seek(max(0, fsize - 131072))
            tail = fh.read().decode("utf-8", "ignore").splitlines()
        for line in reversed(tail):
            try:
                rec = json.loads(line)
            except Exception:
                continue
            if rec.get("type") == "assistant":
                u = (rec.get("message") or {}).get("usage") or {}
                if u:
                    used = (u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0)
                            + u.get("cache_creation_input_tokens", 0))
                    ctx_pct = 100 * used / size
                    break
    except Exception:
        pass
if ctx_pct is not None:
    ctx_left = k(max(0, round(size * (1 - ctx_pct / 100))))
    bar, pct_s = meter(ctx_pct, warn=60, crit=85)
    seg = f"{DIM}ctx{RST} {bar} {pct_s} {DIM}· {ctx_left} left{RST}"
    if has_state and ctx_pct >= 40:
        seg += " " + c("33", "⟳ clear-worthy")
    l2.append(seg)

# usage limits (Pro/Max): warn at 50% per the plugin's design
def window(wname, label):
    w = rl.get(wname) or {}
    pct = w.get("used_percentage")
    if pct is None:
        return None
    bar, pct_s = meter(pct, width=6, warn=50, crit=80)
    seg = f"{DIM}{label}{RST} {bar} {pct_s}"
    resets = w.get("resets_at")
    if resets:
        seg += f" {DIM}↻ {time.strftime('%H:%M', time.localtime(resets))}{RST}"
    return seg

for wname, label in (("five_hour", "5h"), ("seven_day", "7d")):
    seg = window(wname, label)
    if seg:
        l2.append(seg)

print(SEP.join(l1))
if l2:
    print(SEP.join(l2))
PY
