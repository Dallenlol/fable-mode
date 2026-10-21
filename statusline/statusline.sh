#!/bin/bash
# Ripple HUD — fable-mode's statusline renderer for Claude Code.
# Receives session JSON on stdin, prints a two-line ANSI HUD:
#   line 1: persona/level, model, branch (+dirty count), cost, spend rate, duration, lines changed
#   line 2: in-flight prompt (elapsed, estimate, current tool) + context meter,
#           cache hit rate, usage-limit meters (5h / 7d, Pro/Max plans) with burn-out warning
# Installed to ~/.claude/fable-mode/statusline.sh by scripts/install-statusline.sh;
# session_start.sh re-syncs the copy so plugin updates propagate.
# Every optional segment is guarded: a failure drops that segment, never the HUD.
set -u
INPUT="$(cat)"

HOOK_INPUT="$INPUT" python3 - <<'PY' 2>/dev/null || printf 'fable'
import json, os, subprocess, time, sys
from datetime import datetime

# Windows consoles default to cp1252, which can't encode the HUD's emoji/box
# glyphs; force UTF-8 so the renderer doesn't crash to the bare fallback.
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

d = json.loads(os.environ["HOOK_INPUT"])
model = (d.get("model") or {}).get("display_name") or "?"
cost = d.get("cost") or {}
cwd = (d.get("workspace") or {}).get("current_dir") or "."
sid = d.get("session_id", "")
tp = d.get("transcript_path")
cw = d.get("context_window") or {}
rl = d.get("rate_limits") or {}
pc = d.get("prompt_cache") or {}
now = time.time()

DATA = os.path.expanduser("~/.claude/fable-mode")
DIM, RST = "\033[2m", "\033[0m"
def c(code, s): return f"\033[{code}m{s}{RST}"
SEP = f"  {DIM}·{RST}  "

def meter(pct, width=8, warn=50, crit=80):
    pct = max(0, min(100, round(pct)))
    color = "32" if pct < warn else ("33" if pct < crit else "31")
    filled = max(1 if pct else 0, min(width, round(pct * width / 100)))
    return c(color, "━" * filled) + c("2;90", "━" * (width - filled)), c(color, f"{pct}%")

def k(n):
    return f"{n / 1000:.1f}k" if n < 1_000_000 else f"{n / 1_000_000:.2f}M"

def dur(s):
    s = max(0, int(s))
    if s < 60:
        return f"{s}s"
    if s < 3600:
        return f"{s // 60}m{s % 60:02d}s"
    return f"{s // 3600}h{s % 3600 // 60:02d}m"

def ts(rec):
    try:
        return datetime.fromisoformat(rec["timestamp"].replace("Z", "+00:00")).timestamp()
    except Exception:
        return None

def tail_lines(path, nbytes):
    size = os.path.getsize(path)
    with open(path, "rb") as fh:
        fh.seek(max(0, size - nbytes))
        lines = fh.read().decode("utf-8", "ignore").splitlines()
    return lines[1:] if size > nbytes else lines  # first line may be cut mid-record

# Transcript records that matter: real user prompts, tool results, assistant messages.
# Shell (`!`) and local-command echoes are logged as user strings but start no turn.
NOT_PROMPT = ("<bash-input>", "<bash-stdout>", "<bash-stderr>", "<local-command", "[Request interrupted")
def classify(rec):
    t = rec.get("type")
    if rec.get("isSidechain") or rec.get("isMeta"):
        return None
    m = rec.get("message") or {}
    if t == "assistant":
        return "end" if m.get("stop_reason") == "end_turn" else "asst"
    if t == "user":
        cont = m.get("content")
        if isinstance(cont, str):
            if cont.startswith("[Request interrupted"):
                return "end"
            return None if cont.lstrip().startswith(NOT_PROMPT) else "prompt"
        if isinstance(cont, list):
            types = {b.get("type") for b in cont if isinstance(b, dict)}
            if "tool_result" in types:
                return "result"
            if any(b.get("type") == "text" and str(b.get("text", "")).startswith("[Request interrupted")
                   for b in cont if isinstance(b, dict)):
                return "end"
            return "prompt" if types else None
    return None

def parse(lines):
    out = []
    for line in lines:
        if '"user"' not in line and '"assistant"' not in line:
            continue
        try:
            rec = json.loads(line)
        except Exception:
            continue
        kind = classify(rec)
        if kind:
            out.append((kind, rec))
    return out

def turn_durations(recs):
    """Prompt -> last end_turn before the next prompt, in seconds."""
    durs, start, last_end = [], None, None
    for kind, rec in recs:
        if kind == "prompt":
            if start is not None and last_end is not None:
                durs.append(last_end - start)
            start, last_end = ts(rec), None
        elif kind == "end" and start is not None:
            last_end = ts(rec)
    if start is not None and last_end is not None:
        durs.append(last_end - start)
    return [x for x in durs if x is not None and x > 0]

def median(xs):
    xs = sorted(xs)
    n = len(xs)
    return None if not n else (xs[n // 2] if n % 2 else (xs[n // 2 - 1] + xs[n // 2]) / 2)

# level pin
level = "auto"
try:
    lv = open(f"{DATA}/level").read().strip()
    if lv in ("lite", "full", "deep"):
        level = lv
except Exception:
    pass

# git branch + dirty count in one call (fast, silent)
branch, dirty = "", 0
try:
    st = subprocess.run(["git", "-C", cwd, "status", "--porcelain=v1", "-b"],
                        capture_output=True, text=True, timeout=1)
    if st.returncode == 0:
        lines = st.stdout.splitlines()
        if lines and lines[0].startswith("## "):
            head = lines[0][3:].replace("No commits yet on ", "")
            branch = "" if head.startswith("HEAD (no branch)") else head.split("...")[0].split(" ")[0]
            lines = lines[1:]
        dirty = len([l for l in lines if l.strip()])
except Exception:
    pass

# transcript tail: shared by the in-flight detector, activity, cache fallback, context fallback
recs = []
try:
    if tp:
        recs = parse(tail_lines(tp, 1_500_000))
except Exception:
    recs = []

# ---- in-flight prompt: elapsed, estimate, current activity ----
flight = None
try:
    last_prompt = max((i for i, (kind, _) in enumerate(recs) if kind == "prompt"), default=None)
    if last_prompt is not None:
        after = recs[last_prompt + 1:]
        started = ts(recs[last_prompt][1])
        last_seen = ts(recs[-1][1]) or started
        # A turn is live until an end_turn/interrupt follows the prompt; ignore a
        # transcript that's gone quiet for an hour (crashed or abandoned session).
        if started and not any(kind == "end" for kind, _ in after) and now - last_seen < 3600:
            flight = {"elapsed": now - started, "after": after}
except Exception:
    flight = None

def estimate():
    """Median prompt duration: this session first, then recent sessions in the same project."""
    durs = turn_durations(recs)[-20:]
    if len(durs) < 3 and tp:
        cache_f = f"{DATA}/eta-cache.json"
        proj = os.path.dirname(tp)
        try:
            cached = json.load(open(cache_f))
        except Exception:
            cached = {}
        hit = cached.get(proj)
        if hit and now - hit.get("at", 0) < 600:
            durs = durs + hit.get("durs", [])
        else:
            pool = []
            others = sorted((os.path.join(proj, f) for f in os.listdir(proj)
                             if f.endswith(".jsonl") and os.path.join(proj, f) != tp),
                            key=os.path.getmtime, reverse=True)[:5]
            for f in others:
                try:
                    pool += turn_durations(parse(tail_lines(f, 1_000_000)))[-20:]
                except Exception:
                    pass
            pool = pool[-40:]
            try:
                cached[proj] = {"at": now, "durs": pool}
                tmp = cache_f + ".tmp"
                json.dump(cached, open(tmp, "w"))
                os.replace(tmp, cache_f)
            except Exception:
                pass
            durs = durs + pool
    m = median(durs)
    if m is None:
        return None
    # fable: crude multiplier — a pinned level shifts the typical turn length
    return m * {"lite": 0.6, "deep": 1.6}.get(level, 1.0)

def short_tool(block):
    name = block.get("name") or "tool"
    inp = block.get("input") or {}
    if name.startswith("mcp__"):
        name = name.split("__")[-1]
    detail = ""
    if name == "Bash":
        detail = (inp.get("command") or "").strip().splitlines()[0] if inp.get("command") else ""
    elif name in ("Read", "Edit", "Write", "NotebookEdit"):
        detail = os.path.basename(inp.get("file_path") or inp.get("notebook_path") or "")
    elif name in ("Grep", "Glob"):
        detail = inp.get("pattern") or ""
    elif name in ("WebFetch",):
        detail = (inp.get("url") or "").split("//")[-1].split("/")[0]
    elif name == "WebSearch":
        detail = inp.get("query") or ""
    elif name in ("Agent", "Task"):
        detail = inp.get("description") or ""
    elif name == "Skill":
        detail = inp.get("skill") or ""
    if name == "Bash" and detail:
        detail = detail.split()[0].split("/")[-1]  # just the program: git, npm, pytest
    if len(detail) > 18:
        detail = detail[:17] + "…"
    return f"{name} {c('2', detail)}" if detail else name

def activity(after):
    # Parallel tool calls arrive as separate assistant records sharing one message id.
    calls, results, last_id = [], set(), None
    for kind, rec in after:
        m = rec.get("message") or {}
        if kind == "asst":
            blocks = [b for b in (m.get("content") or []) if isinstance(b, dict) and b.get("type") == "tool_use"]
            if blocks:
                if m.get("id") != last_id:
                    calls, last_id = [], m.get("id")
                calls += blocks
        elif kind == "result":
            for b in m.get("content") or []:
                if isinstance(b, dict) and b.get("tool_use_id"):
                    results.add(b["tool_use_id"])
    pending = [b for b in calls if b.get("id") not in results]
    if not pending:
        return c("2", "✻ thinking")
    seg = c("36", "▸ ") + short_tool(pending[-1])
    if len(pending) > 1:
        seg += c("2", f" +{len(pending) - 1}")
    return seg

flight_seg = None
if flight:
    try:
        el = flight["elapsed"]
        seg = c("33", f"⏳ {dur(el)}")
        try:
            est = estimate()
            if est:
                left = est - el
                seg += " " + (c("2", f"~{dur(left)} left") if left > 0 else c("33", "running long"))
        except Exception:
            pass
        try:
            seg += "   " + activity(flight["after"])
        except Exception:
            pass
        flight_seg = seg
    except Exception:
        flight_seg = None

# ---- line 1: identity (calm: only what you glance at) ----
state_loop = os.path.exists(f"{DATA}/state-loop")
has_state = state_loop and os.path.exists(os.path.join(cwd, ".fable-state.md"))
first = c("35;1", "◈ Ripple HUD")
if level == "deep":
    first += " " + c("1;97;41", " deep ")
elif level != "auto":
    first += " " + c("2", level)
l1 = [first, model]
if state_loop:
    l1.append(c("32", "✎ state") if has_state else f"{DIM}✎ state ∅{RST}")
if branch:
    l1.append(c("34", branch) + (" " + c("33", f"●{dirty}") if dirty else ""))
usd = cost.get("total_cost_usd")
mins = (cost.get("total_duration_ms") or 0) // 60000
if usd is not None:
    seg = c("33", f"${usd:.2f}")
    if mins >= 1 and usd / mins >= 0.25:  # spend rate only when it's worth noticing
        rate = usd / mins
        seg += " " + c("31" if rate >= 1 else "33", f"${rate:.2f}/m")
    l1.append(seg)

# ---- line 2: live prompt, then meters (each appears only when it says something) ----
l2 = []
if flight_seg:
    l2.append(flight_seg)

# context: official fields first, transcript-tail fallback for older versions
ctx_pct = cw.get("used_percentage")
size = int(os.environ.get("FABLE_CTX_LIMIT", 0)) or cw.get("context_window_size") or 200000
if ctx_pct is None:
    for kind, rec in reversed(recs):
        u = (rec.get("message") or {}).get("usage") or {}
        if kind in ("asst", "end") and u:
            used = (u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0)
                    + u.get("cache_creation_input_tokens", 0))
            ctx_pct = 100 * used / size
            break
if ctx_pct is not None:
    bar, pct_s = meter(ctx_pct, warn=60, crit=85)
    seg = f"{DIM}ctx{RST} {bar} {pct_s}"
    if ctx_pct >= 60:
        seg += f" {DIM}{k(max(0, round(size * (1 - ctx_pct / 100))))} left{RST}"
    if has_state and ctx_pct >= 40:
        seg += " " + c("33", "⟳ /clear")
    l2.append(seg)

# cache hit rate: hidden while healthy (>=80% and warm)
try:
    hr = pc.get("hit_ratio")
    if hr is None:
        rd = wr = fresh = 0
        seen = set()
        for kind, rec in recs[-200:]:
            m = rec.get("message") or {}
            u = m.get("usage") or {}
            if kind in ("asst", "end") and u and m.get("id") not in seen:
                seen.add(m.get("id"))
                rd += u.get("cache_read_input_tokens", 0)
                wr += u.get("cache_creation_input_tokens", 0)
                fresh += u.get("input_tokens", 0)
        hr = rd / (rd + wr + fresh) if rd + wr + fresh else None
    cold = pc.get("caching_observed") and pc.get("warm") is False
    if hr is not None and (hr < 0.8 or cold):
        p = round(hr * 100)
        l2.append(f"{DIM}cache{RST} " + c("33" if p >= 50 else "31", f"{p}%") + (" " + c("33", "cold") if cold else ""))
except Exception:
    pass

# usage limits (Pro/Max): 5h always, 7d from 50%; reset time from 50%;
# warn when the current burn rate would exhaust the window before it resets
WINDOW_SECS = {"five_hour": 5 * 3600, "seven_day": 7 * 86400}
def window(wname, label):
    w = rl.get(wname) or {}
    pct = w.get("used_percentage")
    if pct is None or (wname == "seven_day" and pct < 50):
        return None
    bar, pct_s = meter(pct, width=6, warn=50, crit=80)
    seg = f"{DIM}{label}{RST} {bar} {pct_s}"
    resets = w.get("resets_at")
    if resets:
        if pct >= 50:
            seg += f" {DIM}↻{time.strftime('%H:%M', time.localtime(resets))}{RST}"
        try:
            spent = now - (resets - WINDOW_SECS[wname])
            if pct >= 10 and spent > 600 and pct < 100:
                to_full = (100 - pct) * spent / pct
                if now + to_full < resets:
                    seg += " " + c("31", f"⚠ full ~{dur(to_full)}")
        except Exception:
            pass
    return seg

for wname, label in (("five_hour", "5h"), ("seven_day", "7d")):
    seg = window(wname, label)
    if seg:
        l2.append(seg)

print(SEP.join(l1))
if l2:
    print(SEP.join(l2))
PY
