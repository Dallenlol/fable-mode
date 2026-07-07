# fable-mode

**Make any Claude model work like a frontier model — Fable 5's judgment, workflow, and token discipline as a Claude Code plugin.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-plugin-orange)](https://code.claude.com/docs/en/plugins)
[![Version](https://img.shields.io/badge/version-1.2.0-green)](.claude-plugin/plugin.json)

Frontier models don't win by writing more — they win by judgment: reading only what matters, fixing root causes instead of symptoms, attacking their own answers before trusting them, and saying what happened in one sentence instead of five paragraphs. `fable-mode` distills that operating style from Claude Fable 5 into a ~1,200-token behavioral layer that loads automatically at the start of every Claude Code session, so cheaper models (Opus, Sonnet, Haiku) work the same way — and spend dramatically fewer tokens doing it.

Honest framing up front: this is a behavioral layer, not a model swap. It can't add raw capability — what it does is close the *process* gaps that separate models in practice: first-plausible-path commitment, unverified answers, bloated context, and padded output.

## Quick start

```
/plugin marketplace add Dallenlol/fable-mode
/plugin install fable-mode@fable-mode-marketplace
```

That's it. The operating style injects automatically on session start, resume, `/clear`, and after compaction. Pick any model (`/model opus`, `/model sonnet`) and work normally. To re-assert it manually mid-session: `/fable-mode:fable-mode`.

## What it does

**1. Runs every task through Fable 5's operating loop.**
Triage the ask (question vs. change request — define DONE first) → understand before touching anything (trace the flow, every caller) → choose the smallest correct approach (reuse > stdlib > dependency > new code; root cause over symptom) → execute (parallel tool batching, targeted edits, no permission-asking for reversible work) → verify (run the check that would fail if you were wrong) → report (outcome in the first sentence).

**2. Routes by difficulty.**
Routine work stays on the cheap path. Genuinely hard problems — novel algorithms, subtle correctness logic, security- or money-critical decisions — escalate into a hard-problem protocol: write the invariants first, generate competing approaches, distrust green test suites, attack your own answer with counterexamples and executable checks, and spawn independent subagent solvers to cross-check when the stakes justify it. Deep tokens go only where they buy correctness.

**3. Enforces token discipline that maps to real billing mechanics.**

| Rule | Why it saves tokens |
|---|---|
| Grep first, read line ranges, never whole files | Input tokens scale with relevance, not file size |
| Never re-read after an edit; never re-derive known facts | Kills the most common duplicated input spend |
| Targeted edits over full-file rewrites | Output cost scales with the diff, not the file |
| Delegate broad exploration to subagents, keep only conclusions | Main context stays small, so **every subsequent turn** is cheaper |
| Batch independent tool calls in one message | Fewer round trips through a growing context |
| Outcome-first replies, `file:line` refs, no pasted code | Output tokens are the most expensive; this is pure savings |

The injected prompt itself costs ~1,200 tokens per session — it pays for itself in the first avoided file re-read.

## Measured

A/B runs on **Opus 4.8**, fable-mode vs. unprompted, same tasks, graded against known ground truth:

- **Routine bug fix** (shared parser crashing, symptom reported in one of two callers): both arms produced the identical root-cause fix. The fable-mode arm used **27% fewer output tokens**, verified against the project's existing test suite instead of inventing new scaffolding, and delivered a **77% shorter** outcome-first report that still contained everything needed.
- **Hard audit** (subtle coverage-losing bug buried in a billing module behind a fully green test suite): both arms found the planted bug — and the fable-mode arm **additionally surfaced a genuine spec ambiguity the control missed**, spending ~2× output tokens on this one task. That asymmetry is the routing working as designed: save everywhere, spend where it buys correctness.

Small-scale evals (one run per condition) — treat them as demonstrations of mechanism, not benchmarks. The savings compound on larger tasks, where reading discipline and context hygiene dominate cost.

## How it works

```
fable-mode/
├── .claude-plugin/
│   ├── plugin.json          # plugin manifest
│   └── marketplace.json     # repo doubles as its own marketplace
├── hooks/
│   ├── hooks.json           # SessionStart → inject the style
│   └── session_start.sh     # strips frontmatter, prints the skill body
└── skills/
    └── fable-mode/
        └── SKILL.md         # the operating style — single source of truth
```

One file holds the entire behavior (`skills/fable-mode/SKILL.md`); the SessionStart hook injects its body into context automatically. No dependencies, no build step, no telemetry, nothing leaves your machine.

## Use on claude.ai (web / desktop / mobile)

Hooks are Claude Code-only, but the skill is portable:

1. Zip the `skills/fable-mode/` folder.
2. On claude.ai: **Settings → Capabilities → Skills** → upload the zip (custom skills require a paid plan).
3. Claude applies it automatically on matching tasks, or ask for "fable mode" explicitly.

## What it is not

It won't make a small model derive novel mathematics like a frontier model, and it can't add knowledge the base model lacks. It also never trades away correctness for brevity: input validation, error handling, security, and verification are explicitly exempt from all token thrift. When brevity and correctness conflict, correctness wins — that rule is in the prompt.

## Local development

```
/plugin marketplace add /path/to/fable-mode
/plugin install fable-mode@fable-mode-marketplace
```

Validate changes with `claude plugin validate .` before pushing.

## License

[MIT](LICENSE)
