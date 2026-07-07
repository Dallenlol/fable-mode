#!/usr/bin/env python3
"""fable-mode eval harness.

A/B-runs each task in evals/tasks/ through headless Claude Code (`claude -p`)
with and without the fable-mode skill injected, grades the results against
ground truth, and prints a markdown table. Stdlib only.

Usage:
  evals/run.py                        # all tasks, both conditions, 1 run each
  evals/run.py --tasks easy-parse-blank --runs 3 --model opus
  evals/run.py --conditions fable     # one condition only
  evals/run.py --yolo                 # --dangerously-skip-permissions (isolated tmp dirs)

Each task directory contains:
  task.json   {"name", "tier", "prompt" (with {DIR} placeholder), "grade": {...}}
  fixture/    files copied to a fresh temp dir per run

Grade keys (all optional):
  check_cmd        shell command run in the temp dir; exit 0 = "correct"
  file_regex       {relpath: regex} — every regex must match that file's content
  file_forbid     {relpath: regex} — no regex may match
  final_regex      [regex, ...] — every regex must match the model's final message
  fixture_unmodified  true — fixture files must be byte-identical after the run
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SKILL = ROOT.parent / "skills" / "fable-mode" / "SKILL.md"
HEADER = "FABLE MODE ACTIVE — apply the following operating style for the entire session:"


def skill_body():
    parts = SKILL.read_text().split("---\n")
    return "---\n".join(parts[2:]).strip()  # drop YAML frontmatter


def tree_hashes(d: Path):
    return {
        str(p.relative_to(d)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(d.rglob("*")) if p.is_file()
    }


def run_claude(prompt, model, yolo, timeout):
    cmd = ["claude", "-p", prompt, "--model", model, "--output-format", "json"]
    if yolo:
        cmd.append("--dangerously-skip-permissions")
    else:
        cmd += ["--permission-mode", "acceptEdits",
                "--allowedTools", "Bash,Edit,Write,Read,Grep,Glob"]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {"result": proc.stdout, "is_error": True, "stderr": proc.stderr[-2000:]}


def grade(cfg, workdir: Path, final_text: str, pre_hashes):
    g, results = cfg.get("grade", {}), {}
    if "check_cmd" in g:
        cmd = g["check_cmd"].replace("{DIR}", str(workdir))
        results["check_cmd"] = subprocess.run(
            cmd, shell=True, capture_output=True, timeout=120).returncode == 0
    for rel, rx in g.get("file_regex", {}).items():
        p = workdir / rel
        results[f"file:{rel}"] = p.exists() and re.search(rx, p.read_text()) is not None
    for rel, rx in g.get("file_forbid", {}).items():
        p = workdir / rel
        results[f"forbid:{rel}"] = (not p.exists()) or re.search(rx, p.read_text()) is None
    for i, rx in enumerate(g.get("final_regex", [])):
        results[f"final:{i}"] = re.search(rx, final_text, re.IGNORECASE) is not None
    if g.get("fixture_unmodified"):
        results["unmodified"] = tree_hashes(workdir) == pre_hashes
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tasks", nargs="*", help="task names (default: all)")
    ap.add_argument("--conditions", nargs="*", default=["control", "fable"])
    ap.add_argument("--runs", type=int, default=1)
    ap.add_argument("--model", default="opus")
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--yolo", action="store_true",
                    help="use --dangerously-skip-permissions (runs are in isolated temp dirs)")
    args = ap.parse_args()

    task_dirs = sorted(d for d in (ROOT / "tasks").iterdir() if (d / "task.json").exists())
    if args.tasks:
        task_dirs = [d for d in task_dirs if d.name in args.tasks]
    if not task_dirs:
        sys.exit("no tasks found")

    body, rows = skill_body(), []
    for td in task_dirs:
        cfg = json.loads((td / "task.json").read_text())
        for cond in args.conditions:
            for i in range(args.runs):
                work = Path(tempfile.mkdtemp(prefix=f"fable-eval-{td.name}-{cond}-"))
                shutil.copytree(td / "fixture", work, dirs_exist_ok=True)
                pre = tree_hashes(work)
                prompt = cfg["prompt"].replace("{DIR}", str(work))
                if cond == "fable":
                    prompt = f"{HEADER}\n\n{body}\n\n---\n\nYour task: {prompt}"
                t0 = time.time()
                print(f"[{td.name} | {cond} | run {i + 1}] ...", file=sys.stderr, flush=True)
                res = run_claude(prompt, args.model, args.yolo, args.timeout)
                final = res.get("result") or ""
                usage = res.get("usage") or {}
                checks = grade(cfg, work, final, pre)
                rows.append({
                    "task": td.name, "tier": cfg.get("tier", "?"), "condition": cond, "run": i + 1,
                    "pass": all(checks.values()) and not res.get("is_error"),
                    "checks": checks,
                    "output_tokens": usage.get("output_tokens"),
                    "num_turns": res.get("num_turns"),
                    "cost_usd": res.get("total_cost_usd"),
                    "final_chars": len(final),
                    "final": final[:3000],
                    "secs": round(time.time() - t0),
                    "workdir": str(work),
                })
                shutil.rmtree(work, ignore_errors=True)

    out = ROOT / "results" / f"{time.strftime('%Y%m%d-%H%M%S')}.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(rows, indent=2))

    print("\n| task | tier | condition | pass | out-tokens | turns | report-chars | secs |")
    print("|---|---|---|---|---|---|---|---|")
    for r in rows:
        print(f"| {r['task']} | {r['tier']} | {r['condition']} | "
              f"{'✅' if r['pass'] else '❌'} | {r['output_tokens']} | "
              f"{r['num_turns']} | {r['final_chars']} | {r['secs']} |")
    fails = [r for r in rows if not r["pass"]]
    print(f"\n{len(rows) - len(fails)}/{len(rows)} passed. Details: {out}")
    for r in fails:
        bad = [k for k, v in r["checks"].items() if not v]
        print(f"  FAIL {r['task']}/{r['condition']}/run{r['run']}: {bad}")


if __name__ == "__main__":
    main()
