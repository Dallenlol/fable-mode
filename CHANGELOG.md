# Changelog

## v1.6.1 — 2026-07-07

- **Breakpoint clearing policy**: the state loop now suggests `/clear` at natural task boundaries (task complete + context above ~40%) instead of on a raw percentage timer, stays quiet mid-task below ~85%, and never right after a turn the user may want to tweak — clearing too often costs more than it saves (cache-rebuild tax). Statusline shows a `⟳ clear-worthy` chip when a breakpoint is available.
- **Provider-neutral skill wording**: subagent and compaction references now degrade gracefully on harnesses without those features — the AGENTS.md export works unchanged on Claude, GPT, Gemini, or local models.
- Regression benchmark on the reworded skill: **Haiku 7/7** (first perfect sweep, marathon task included).

## v1.6.0 — 2026-07-07

- **State loop** (`/fable-mode:fable-state on`): the model maintains a `.fable-state.md` project memory file at the end of every substantive turn; `/clear` whenever the context meter runs hot and the next session auto-resumes from the file — continuation context in ~2k tokens instead of the full chat history. Toggleable, off by default; statusline shows a `✎ state` indicator.
- **Marathon eval tier**: a 12-file orders-service fixture with a cross-file root cause (float truncation in the one shared money module), measuring the reading-discipline and root-cause behaviors that only show up beyond toy tasks.
- **Prompt-variant testing**: `evals/run.py --skill-file` A/Bs alternate SKILL.md versions — prompt changes are now measured, not guessed.
- **claude.ai one-step install**: releases ship a prebuilt `fable-mode-skill.zip` asset.
- `/fable-stats` now includes an estimated-savings line (clearly labeled as an estimate, derived from published benchmark ratios).
- README visuals (statusline HUD, benchmark chart), CONTRIBUTING.md, issue templates, Windows notes.

## v1.5.2 — 2026-07-07

Full production review pass: bulleted choose-step for small-model instruction-following, judgment-call flagging on ambiguous specs, model column + crash-safe eval runner (timeouts no longer lose results), settings.json backup on statusline install, `FABLE_CTX_LIMIT` honored again, three-way benchmark documented — and its results published: **Sonnet + fable-mode matched Fable 5 on all 6 graded outcomes at $2.88 vs $10.71 (73% cheaper).**

## v1.5.1 — 2026-07-07

Eight more craftsman rules: the one-line rung, edge-case-correct choices between equal options, deletion over addition, edit over create, no re-arguing when the user insists, YAGNI for tests, "skipped X — add when Y" reporting, requested-explanation-is-never-debt.

## v1.5.0 — 2026-07-07

Plan usage-limit meters in the statusline (5h/7d, yellow at 50%), INSTALL.md setup guide, the **Fable** persona (displayName, `fable off` escape hatch), sharper craftsman mechanics (rung zero, `fable:` ceiling comments, ship-and-offer, anti-drift clause).

## v1.4.0 — 2026-07-07

Statusline HUD (context meter, session tokens, cost, level) and the `/fable-level` pin command.

## v1.3.0 — 2026-07-07

Auto-routed intensity levels (lite/full/deep), local token stats + `/fable-stats`, AGENTS.md export, the reproducible eval harness with grading self-test, CI.

## v1.2.0 — 2026-07-07

Initial public release: the Fable operating loop, difficulty routing with the hard-problem protocol, token discipline, SessionStart injection, repo-as-marketplace packaging.
