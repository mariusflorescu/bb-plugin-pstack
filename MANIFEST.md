# Manifest

## Source

- Upstream: `cursor/plugins`, path `pstack/`.
- Pinned commit: see `UPSTREAM` (machine-readable, bumped by `scripts/sync-upstream.mjs`). At the time of writing, `0e9af5e170fed0953e3028d0554adbabbe0027cb`, pstack `0.15.5`.
- License: MIT, Copyright (c) 2026 Lauren Tan (`LICENSE`, retained verbatim).
- bb packaging (`package.json`, the `server.ts` skill switches) started from `wy3z/bb-plugin-pstack` at `32f7908`. The skill text from that repo was replaced with upstream content and re-adapted.

## Layout

bb ships each `skills/<name>/` directory into a thread and nothing else. Anything a skill needs at runtime lives inside its own directory.

| Upstream path | Here |
|---|---|
| `pstack/skills/<name>/` | `skills/<name>/`, except the aliases below |
| `pstack/agents/poteto-agent.md` | Dropped. A child's brief starts with `/poteto-mode` instead. |
| `pstack/agents/comment-sicko.md` | `skills/no-comments/references/comment-sicko.md` |
| `pstack/README.md` | `UPSTREAM-README.md` (verbatim) |
| `pstack/docs/` | `docs/`, adapted to bb (reference only, not shipped to threads) |
| `pstack/automations/` | Dropped (Cursor automations) |
| `pstack/.cursor-plugin/` | Dropped (Cursor plugin manifest) |

`scripts/sync-upstream.mjs` applies this table (`mapPath`) to every upstream change.

## Aliases

| Upstream name | Here | Why |
|---|---|---|
| `arena` | `pstack-arena` | Collides with a personal `arena` skill in `~/.claude/skills` / `~/.agents/skills` |
| `tdd` | `pstack-tdd` | Same, `tdd` |
| `blast-radius` | `pstack-blast-radius` | Same, `blast-radius` |

The sync applies the aliases to upstream's base and new versions before merging, so alias renames never conflict. `UPSTREAM-README.md` is exempt and stays byte for byte upstream's.

## Adaptations

[BB-NATIVE.md](./BB-NATIVE.md) is the full contract. In short: delegation is `bb thread spawn --parent-self` with the role's provider, model and effort from the plugin's `models` setting (injected into every thread by `server.ts`); no model slugs in skills; transcripts come from `bb thread log`; wake-ups use `bb thread wait` or `bb automation`; cloud agents become worktree children; `gh` is the only forge; Cursor-only tools and skills are replaced by their bb equivalents or dropped. Two frontmatter display names (`Poteto Mode`, `Make Bot UI`) are lowercased because bb requires `name` to equal the directory.

## Verification

`node scripts/check-bb-native.mjs` checks every skill: no Cursor mechanisms in shipped text, no BB CLI usage the contract rules out (child lists without `--include-hidden`, provider queries without a host, pstack trunk reads without `read-from-trunk.sh`, waits described as timing out, a `--base-branch` other than `"$(git rev-parse HEAD)"` or `origin/<branch>`), frontmatter `name` equal to the directory, relative links resolving inside `skills/`, bold skill names resolving to a skill directory (a short principle name to `principle-<name>/`), and `server.ts` listing exactly the skill directories.

`node --test scripts/` runs the sync script against throwaway repos (merges, local deletions, file modes, symlinks, the verbatim README, aborting before any write), checks `UPSTREAM-README.md` against the pinned upstream README, renders the injected delegation rules (per-role overrides, `inherit-parent`, the 4096-character limit), runs the checker on a tree with broken bold skill names, and regenerates the `server.ts` skill list. The script tests run from directories with spaces in their paths.
