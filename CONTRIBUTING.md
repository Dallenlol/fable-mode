# Contributing

The bar for every change: does it get cheaper models closer to frontier-quality output, or does it cut tokens without cutting quality? If neither, it probably doesn't belong.

## Ground rules

- **`skills/fable-mode/SKILL.md` is the product.** Every sentence in it costs injection tokens in every session for every user — additions must earn their keep. Short imperative rules beat compound prose (smaller models follow them better).
- **Prompt changes require benchmark evidence.** Run the suite before and after with your variant: `evals/run.py --skill-file path/to/your-SKILL.md --model haiku` (haiku is the cheapest signal). Include both tables in the PR.
- **After editing the skill**, run `scripts/build-agents-md.sh` — CI fails if `AGENTS.md` drifts out of sync.
- **All checks must pass locally**: `python3 evals/selftest.py` and `claude plugin validate .`
- New eval tasks are very welcome — see [`evals/README.md`](evals/README.md) for the format. Good tasks have unambiguous ground truth and a tempting wrong answer.

## What gets merged

Measured improvements, new graded eval tasks, portability fixes, doc corrections. What doesn't: prompt additions without benchmark deltas, dependencies (the repo is deliberately stdlib-only), telemetry of any kind.
