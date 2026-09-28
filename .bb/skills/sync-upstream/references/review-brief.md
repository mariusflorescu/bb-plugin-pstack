# Adversarial review: pstack on BB against Cursor's pstack

You are an adversarial reviewer from a different model family than the authors. Find where this repo's BB port of pstack is wrong. Assume at least one real defect exists in your scope until you have checked every line of it.

## Sources

- **Cursor's pstack, the reference.** Cursor's own repository, `https://github.com/cursor/plugins`, path `pstack/`, fetched into this repo as git objects. The skills this repo bundles from cursor-team-kit come from the same repository, path `cursor-team-kit/`. Read a file with `git show <UPSTREAM_SHA>:<upstream path>` and list with `git ls-tree -r --name-only <UPSTREAM_SHA> -- pstack/ cursor-team-kit/`. `<UPSTREAM_SHA>` is given in your scope below. Confirm provenance once with `git rev-parse --verify <UPSTREAM_SHA>^{commit}` and `git log -1 --format='%H %an %s' <UPSTREAM_SHA>`.
- **This repo's port.** The working tree at `HEAD`: `skills/`, `server.ts` (the injected pstack delegation rules and the `models` setting), `BB-NATIVE.md` (the translation contract; read it first, in full).
- **Path mapping.** `pstack/skills/<name>/` is `skills/<name>/`, except `arena`, `tdd` and `blast-radius`, which are `skills/pstack-<name>/`. `pstack/agents/comment-sicko.md` is `skills/no-comments/references/comment-sicko.md`. `pstack/agents/poteto-agent.md`, `pstack/automations/` and `pstack/.cursor-plugin/` are dropped by design. `pstack/README.md` is `UPSTREAM-README.md` (verbatim). `pstack/docs/` is `docs/`. For each `bundle=` line in `UPSTREAM`, `cursor-team-kit/skills/<name>/` is `skills/<name>/`, and `cursor-team-kit/LICENSE` is that skill's `LICENSE`.
- **BB itself.** `bb <cmd> --help` and `bb guide <chapter>` (`threads`, `automations`, `environments`, `agent-configuration`, `plugins`, `providers`, `browser`, `terminals`, `json`).

## What to check, for every file in scope

Compare our file with Cursor's file line by line.

1. **Fidelity.** Every Cursor instruction changed or deleted: is the BB version equivalent in intent? Flag lost behavior (a deleted passage that had a real BB equivalent), weakened rules or gates, and invented behavior neither Cursor nor BB requires.
2. **BB correctness.** Every `bb` command, flag, environment variable and path must exist and mean what the text says. Verify each with `--help` or the guide.
3. **Delegation contract.** Children are BB child threads per the injected rules, with a named role. No provider-native subagent tool, no model slugs, one child per panel entry, worktrees only for parallel writers with a pinned base, results collected with `bb thread wait` then `bb thread output`.
4. **Safety.** Unauthenticated endpoints, reads of other projects' or users' threads, external writes the user did not ask for, deletion without a gate. Cursor's own autonomy rule in poteto-mode ("external actions proceed without asking") is kept by the owner's decision: do not report it.
5. **Consistency.** Role names match `DEFAULT_MODELS` in `server.ts`. Links and bold skill names resolve. The same mechanism is described the same way across skills.
6. **Leftovers.** Cursor concepts the regex checker (`node scripts/check-bb-native.mjs`) cannot see.
7. **Both providers.** Every skill must work the same in a Claude Code thread and in a Codex thread (`BB-NATIVE.md`, the `disable-model-invocation`, `paths` and `poteto-agent` rows). A skill a brief or the user runs by name uses the provider's syntax (`/<name>` on Claude Code, `$<name>` on Codex); a frontmatter flag one provider ignores has its stand-in (`agents/openai.yaml`, the `paths` line `server.ts` injects); no instruction leans on a tool or behavior only one provider has without saying what the other does.

## Convergence

- A previous round's finding that was rejected with evidence is listed under "Settled" in your scope. Do not raise it again unless you have new evidence, and say what is new.
- Report only defects. Style preferences and wording you would merely phrase differently are not findings.
- If your scope has no defects, your report says `NO FINDINGS` on its first line.

## Rules

- Read-only. No file edits, no git writes, no spawning or messaging threads, no automations, no plugin config changes.
- Evidence or it did not happen: every finding cites our `file:line`, Cursor's text (`<UPSTREAM_SHA>:<upstream path>:<line>`) or "new", and the `bb` help or guide text that proves a BB claim wrong.

## Report (your final message)

First line: `NO FINDINGS` or `FINDINGS: <n>`.

1. Findings, most severe first. Each: severity (`blocker` breaks the skill or is unsafe, `major` loses or distorts behavior, `minor` a real but small defect), `file:line`, what Cursor says, what we say, why it is wrong, the concrete fix.
2. `bb` commands and flags you verified, one line each.
3. Files you compared in full with no findings, one line each.
