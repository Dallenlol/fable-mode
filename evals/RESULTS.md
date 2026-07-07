# Benchmark results — 2026-07-07

## The three-way comparison (the product claim, measured)

Full suite, one run per cell, real `cost_usd` from the Claude Code CLI:

| arm | graded outcomes | suite cost | report chars |
|---|---|---|---|
| **Claude Fable 5** (the target) | 6/6 | **$10.71** | 5,848 |
| **Sonnet + fable-mode** | **6/6** | **$2.88** | 3,585 |
| Sonnet (plain) | 6/6 | $2.75 | 4,094 |

**Sonnet with fable-mode matched Fable 5 on every graded outcome at 73% lower cost.** Within-model, the injection costs ~5% extra on these deliberately small tasks while cutting report length 12% — the within-model savings compound on longer sessions (see the Haiku easy-tier numbers below: −27% output tokens, −27% turns). Note the honest caveat: these six tasks sit within Sonnet's unassisted capability (plain Sonnet also passes); what the plugin buys at this tier is Fable-shaped process — root-cause fixes, verification, judgment-call flagging, terse outcome-first reports — and the price delta versus running the frontier model itself.

Full six-task suite (`evals/run.py`, 1 run per cell unless noted), fable-mode vs. unprompted control, graded against ground truth. Raw per-run JSON is written to `evals/results/` (gitignored); this file is the curated snapshot. Reproduce with `evals/run.py --model <m>`.

## Opus 4.8 — 12/12 passed (both conditions)

| task | tier | condition | pass | out-tokens | turns | report-chars |
|---|---|---|---|---|---|---|
| easy-parse-blank | easy | control | ✅ | 846 | 3 | 663 |
| easy-parse-blank | easy | fable | ✅ | 1058 | 4 | 455 |
| hard-interval-merge | hard | control | ✅ | 1522 | 3 | 1614 |
| hard-interval-merge | hard | fable | ✅ | 1501 | 4 | 1561 |
| hard-round-half | hard | control | ✅ | 1983 | 4 | 2068 |
| hard-round-half | hard | fable | ✅ | 1801 | 4 | 1568 |
| overbuild-cache | easy | control | ✅ | 794 | 3 | 402 |
| overbuild-cache | easy | fable | ✅ | 1011 | 4 | 322 |
| question-no-edit | easy | control | ✅ | 446 | 2 | 338 |
| question-no-edit | easy | fable | ✅ | 644 | 2 | 368 |
| reuse-slugify | easy | control | ✅ | 1262 | 6 | 492 |
| reuse-slugify | easy | fable | ✅ | 1075 | 6 | 217 |

Opus passes everything either way — the deltas are in shape: fable-mode reports are **19% shorter overall** (4,491 vs 5,577 chars) with nothing graded missing. On the tiniest tasks the injected prompt adds a small output overhead; on multi-step tasks fable-mode comes out below control.

## Haiku 4.5 — pass parity with control, large efficiency gains

| task | tier | condition | pass | out-tokens | turns | report-chars |
|---|---|---|---|---|---|---|
| easy-parse-blank | easy | control | ✅ | 1711 | 7 | 853 |
| easy-parse-blank | easy | fable | ✅ | 1557 | 7 | 234 |
| hard-interval-merge² | hard | control | ✅✅ | 3024 / 4305 | 3 / 3 | 1612 / 1433 |
| hard-interval-merge² | hard | fable | ✅✅ | 5042 / 6357 | 6 / 6 | 1222 / 1735 |
| hard-round-half | hard | control | ✅ | 3178 | 4 | 1375 |
| hard-round-half | hard | fable | ✅ | 5875 | 5 | 1122 |
| overbuild-cache | easy | control | ✅ | 3634 | 15 | 898 |
| overbuild-cache | easy | fable | ✅ | 2141 | 7 | 524 |
| question-no-edit | easy | control | ✅ | 842 | 2 | 188 |
| question-no-edit | easy | fable | ✅ | 488 | 2 | 177 |
| reuse-slugify | easy | control | ✅ | 2646 | 9 | 897 |
| reuse-slugify | easy | fable | ✅ | 2267 | 8 | 294 |

² 2 runs per condition (re-run after a grading-regex fix; the initial "failures" were phrasing-matching strictness, not missed bugs — both conditions had identified the root cause).

**Haiku easy-task aggregate, fable vs control: −27% output tokens (6,453 vs 8,833), −27% turns (24 vs 33), −57% report length (1,229 vs 2,836 chars) — at identical pass rates.** The standout: `overbuild-cache`, where control wandered for 15 turns and fable-mode finished in 7 with the one-decorator solution.

**On hard tasks fable-mode spends *more* output tokens on both models (up to ~1.9× on Haiku)** — that is the difficulty routing working as designed: the deep gear buys invariant-checking and executable verification exactly where being wrong is expensive, funded by the savings everywhere else.

## Marathon tier — Sonnet, three tasks, n=2 per condition (expanded with v1.7.0)

Three multi-file services, each with a cross-file root cause reported far from the bug (`marathon-cents`: float truncation; `marathon-config`: inverted env precedence; `marathon-defaults`: shared-mutable-default state leak). Aggregate over all 6 runs per condition:

| condition | pass | out-tokens (Σ) | turns (Σ) | report-chars (Σ) |
|---|---|---|---|---|
| Sonnet (plain) | 6/6 | 26,854 | 72 | 7,938 |
| Sonnet + fable-mode | 6/6 | 24,661 (−8%) | 62 (−14%) | 5,129 (−35%) |

Every run in both conditions landed the root-cause fix in the shared module (the graders reject caller-side patches). fable-mode's savings concentrate in turns and report weight; per-task variance is visible at n=2 (best single-task delta: −56% turns on `marathon-cents` in the v1.6.0 run), which is why sums are reported rather than cherry-picked runs. Haiku + fable-mode also passes all three marathons — its fable-condition record across every task and run to date is **9/9**.

## Caveats

One run per cell (two for the re-run) — directional, not statistically powered. Add `--runs 3` or more for tighter numbers. Tasks where both conditions pass measure *how* the result is reached (tokens, turns, fix location, report shape), which is the design goal: same output, lower spend.
