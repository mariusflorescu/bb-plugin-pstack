---
name: sync-upstream
description: Pull new upstream pstack changes (cursor/plugins, path pstack/) into this BB plugin, translate anything Cursor-native to BB-native, and open one PR. Run daily by a BB automation; also for "sync upstream", "update pstack from cursor".
---

# Sync upstream pstack

You keep this plugin current with upstream pstack without losing its BB adaptations. The deliverable is one open PR against `mariusflorescu/bb-plugin-pstack`, or a one-line "up to date". Never merge.

## Steps

1. **Start clean.** You run in a fresh worktree of this repo. Confirm `git status --porcelain` is empty. If an open PR already has a head branch starting `sync/upstream-`, find it with `GH_TOKEN=$(gh auth token -u mariusflorescu) gh pr list --repo mariusflorescu/bb-plugin-pstack --state open --json number,headRefName`, check that branch out and continue from it, so one PR accumulates until it is merged. Otherwise stay on `main`.

2. **Run the sync.** `node scripts/sync-upstream.mjs`. The first line of output is the status.
   - `up-to-date`: reply with that line and stop. Do not create a branch or PR.
   - `applied` or `conflicts`: continue. On `main`, create `sync/upstream-<new short sha>` first (`git switch -c`).

3. **Resolve conflicts.** For each file listed under "conflicts to resolve", read the upstream change with `git diff <old sha> <new sha> -- pstack/<upstream path>` (both SHAs are on the status line; `refs/upstream/main` holds the fetched upstream). Keep our BB adaptation and bring in upstream's intent, translated per `BB-NATIVE.md`. Leave no conflict markers: `grep -rn '^<<<<<<<\|^>>>>>>>' skills` must print nothing.

4. **Translate what came in.** Read the whole upstream diff for the new range, not only the conflicts. Every Cursor mechanism in the incoming lines becomes its BB mechanism per `BB-NATIVE.md`. Then run `node scripts/check-bb-native.mjs` and fix every finding. If upstream introduced a Cursor mechanism the contract does not cover, add a row to `BB-NATIVE.md` and a rule to `scripts/check-bb-native.mjs` in the same PR, then apply it.

5. **Keep the plugin whole.** A new or removed skill directory needs `SKILL_NAMES` and `SKILL_SUMMARIES` in `server.ts` updated (the checker flags a mismatch). A new skill whose name collides with a skill in `~/.claude/skills`, `~/.agents/skills` or `~/.bb/skills` gets a `pstack-` alias: add it to `ALIASED` in `scripts/sync-upstream.mjs` and to the aliases table in `MANIFEST.md`. Typecheck with `npm ci --ignore-scripts && npx tsc --noEmit --skipLibCheck`.

6. **Update the manifest.** In `MANIFEST.md`, set the pinned commit to the new SHA and the upstream version to the one in `git show refs/upstream/main:pstack/.cursor-plugin/plugin.json`. `UPSTREAM` was already bumped by the script.

7. **Commit, push, open the PR.** One signed commit, `Sync upstream pstack <old short>..<new short>`, with the upstream commit list in the body. `git push -u origin HEAD`. Open the PR (or, when continuing an open one, comment on it) with `GH_TOKEN=$(gh auth token -u mariusflorescu) gh pr create --repo mariusflorescu/bb-plugin-pstack --base main`. The body lists the upstream commits, each conflict and how you resolved it, each Cursor mechanism you translated, and the checker's summary line.

**Reply:** the status line, the PR link as `https://github.com/mariusflorescu/bb-plugin-pstack/pull/<number>`, and anything you could not translate with confidence.
