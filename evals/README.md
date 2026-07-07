# fable-mode evals

Reproducible A/B benchmark: each task runs through headless Claude Code (`claude -p`) twice — once with the fable-mode skill injected, once without — then gets graded against known ground truth (does the fix land at the root cause? did the model avoid editing files it was only asked about? did it catch the bug the green test suite hides?). Token usage and turn counts come from the CLI's JSON output, so the numbers are real, not estimated.

## Run it

```bash
evals/run.py                                  # all 6 tasks, both conditions, 1 run each
evals/run.py --runs 3 --model opus            # more statistical weight
evals/run.py --tasks hard-interval-merge      # one task
evals/run.py --conditions fable               # one condition
```

Requires the `claude` CLI, authenticated. Runs spend tokens on your account — the full suite at `--runs 3` is roughly 36 headless sessions. Each run executes in a fresh temp directory that is deleted afterward. By default runs use `--permission-mode acceptEdits` with a fixed tool allowlist; pass `--yolo` to use `--dangerously-skip-permissions` instead (acceptable here because every run is confined to its own throwaway temp dir).

Results print as a markdown table and are saved to `evals/results/<timestamp>.json` (gitignored except for curated snapshots).

## Task set

| Task | Tier | What it measures |
|---|---|---|
| `easy-parse-blank` | easy | Root-cause instinct: symptom reported in one caller, real bug in the shared parser |
| `question-no-edit` | easy | Triage: a question must produce an assessment, not code changes |
| `reuse-slugify` | easy | Reuse ladder: the helper already exists — use it, don't reimplement |
| `overbuild-cache` | easy | YAGNI: `functools.lru_cache` beats a hand-rolled cache class |
| `hard-interval-merge` | hard | Green-suite trap: coverage-losing merge bug the test suite never exercises |
| `hard-round-half` | hard | Spec-vs-implementation: `round()` is banker's rounding; the docstring demands half-away-from-zero |

## Adding a task

Create `evals/tasks/<name>/` with a `fixture/` directory and a `task.json`:

```json
{
  "name": "my-task",
  "tier": "easy | hard",
  "prompt": "... {DIR} is replaced with the temp fixture path ...",
  "grade": {
    "check_cmd": "cd {DIR}/src && python3 test_x.py",
    "file_regex": {"src/x.py": "must-match"},
    "file_forbid": {"src/x.py": "must-not-match"},
    "final_regex": ["must appear in the final message"],
    "fixture_unmodified": true
  }
}
```

Good tasks have unambiguous ground truth and a tempting wrong answer. A task both conditions always pass (or always fail) measures nothing — the interesting ones separate *how* the result is reached: fix location, verification behavior, token spend, report shape.
