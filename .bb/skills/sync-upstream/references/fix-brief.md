# Reconcile review findings: pstack on BB

A reviewer, from another model family unless its scope section says it shares yours, compared your scope with Cursor's pstack and with BB's real CLI. Its report is appended below. Act on it with independent judgment.

## Sources

- Cursor's pstack: `git show <UPSTREAM_SHA>:<upstream path>` (Cursor's own commit, fetched from `https://github.com/cursor/plugins`). Path mapping: `pstack/skills/<name>/` is `skills/<name>/` except `arena`, `tdd`, `blast-radius` (`skills/pstack-<name>/`). For each `bundle=` line in `UPSTREAM`, `cursor-team-kit/skills/<name>/` is `skills/<name>/`, and `cursor-team-kit/LICENSE` is that skill's `LICENSE`.
- `BB-NATIVE.md` (read it first), `server.ts` (injected delegation rules), `bb <cmd> --help`, `bb guide <chapter>`.

## Rules

- For each finding: verify it yourself first (the cited lines, Cursor's text, `bb` help or source, the script's behavior). Then fix it, or reject it with concrete evidence. A finding is not true because the reviewer said so, and not false because it is inconvenient.
- Fix at the root. Keep Cursor's wording wherever it is harness-neutral. Prefer a concrete `bb` mechanism over prose. A script change is proven by running the script or its test.
- Stay inside the files in your scope. List anything needed elsewhere under "for the parent".
- No git writes (no add, commit, stash, checkout, reset, restore, push). No spawning or messaging threads, no automations, no plugin config changes.
- Gate: `node scripts/check-bb-native.mjs` must be clean for your files, and `node --test scripts/` must pass if you touched `scripts/` or `server.ts`.

## Report (your final message)

1. Per finding: `fixed` (what changed, `file:line`) or `rejected` (the evidence). Rejections are passed to the next review round as settled.
2. Anything for the parent.
3. Checker output (and test output if run).

## The review
