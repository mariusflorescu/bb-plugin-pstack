# Manifest

## Source

- Upstream: `cursor/plugins`, path `pstack/`.
- Pinned commit: see `UPSTREAM` (machine-readable, bumped by `scripts/sync-upstream.mjs`). At the time of writing, `0e9af5e170fed0953e3028d0554adbabbe0027cb`, pstack `0.15.5`.
- License: MIT, Copyright (c) 2026 Lauren Tan (`LICENSE`, retained verbatim).
- bb packaging (`package.json`, the `server.ts` skill switches) started from `wy3z/bb-plugin-pstack` at `32f7908`. The skill text from that repo was replaced with upstream content and re-adapted.
- `skills/deslop/`, `skills/thermo-nuclear-code-quality-review/` and `skills/what-did-i-get-done/` come from `cursor/plugins`, path `cursor-team-kit/skills/`, at commit `adf3218ca2f5b9971eedc07a76bef22df7701539`. The first two are unchanged since `ecc249f`, where they were first copied. They're verbatim, since all three are harness-neutral. Each directory carries cursor-team-kit's MIT `LICENSE` (Copyright (c) 2026 Cursor). The daily sync reads only `pstack/`, so it doesn't update them. Re-copy them by hand, and run `node scripts/sync-server-skills.mjs` afterwards. cursor-team-kit's `agents/thermo-nuclear-code-quality-review.md` is dropped, like every Cursor agent file. The skill runs in the thread that invokes it.

## Layout

bb ships each `skills/<name>/` directory into a thread and nothing else. Anything a skill needs at runtime lives inside its own directory.

| Upstream path | Here |
|---|---|
| `pstack/skills/<name>/` | `skills/<name>/`, except the aliases below |
| `pstack/agents/poteto-agent.md` | Dropped. A child's brief starts with poteto-mode in the child's syntax instead: `/poteto-mode` on Claude Code, `$poteto-mode` on Codex. |
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

[BB-NATIVE.md](./BB-NATIVE.md) is the full contract. In short: delegation is `bb thread spawn --parent-self` with the role's provider, model and effort from the plugin's `models` setting (injected into every thread by `server.ts`); no model slugs in skills; transcripts come from `bb thread log`; wake-ups use `bb thread wait` or `bb automation`; cloud agents become worktree children; `gh` is the only forge; Cursor-only tools and skills are replaced by their bb equivalents or dropped. Two frontmatter display names (`Poteto Mode`, `Make Bot UI`) are lowercased because bb requires `name` to equal the directory, and poteto-mode drops Cursor's mode fields (`mode`, `icon`, `color`, `reminder`), which bb has no equivalent for. Every user-invoked skill (`disable-model-invocation: true`) also ships a generated `agents/openai.yaml`, because Codex reads that file and not the flag; Codex runs such a skill as `$<name>`, Claude Code as `/<name>`. `server.ts` tells every provider to load a `paths` skill for matching files. typescript-best-practices keeps upstream's `paths` but drops `disable-model-invocation`, because Claude Code will not load a skill that sets it for the model.

## Verification

Run `npm ci --ignore-scripts` once first: the scripts parse frontmatter with the `yaml` dev dependency.

`node scripts/check-bb-native.mjs` checks every skill: no Cursor mechanisms in shipped text, no BB CLI usage the contract rules out (thread lists without `--include-hidden`, provider queries without a host, pstack trunk reads without `read-from-trunk.sh`, waits described as timing out, a `--base-branch` on a line that names neither `"$(git rev-parse HEAD)"` nor `origin/<branch>`), frontmatter `name` equal to the directory, frontmatter that parses as YAML, `agents/openai.yaml` present exactly for user-invoked skills, no skill that is both user-invoked and path-loaded, a brief that runs a skill by `/<name>` also giving `$<name>`, relative links resolving inside `skills/`, bold skill names resolving to a skill directory (a short principle name to `principle-<name>/`), and `server.ts` listing exactly the skill directories.

`node --test scripts/` runs the sync script against throwaway repos (merges, local deletions, file modes, symlinks, the verbatim README, aborting before any write), checks `UPSTREAM-README.md` against the pinned upstream README, renders the injected delegation rules for Claude Code and Codex (per-role overrides, `inherit-parent`, the 4096-character limit with any number of `paths` skills, the `paths` lines and the Codex-only `$<name>` line), parses frontmatter with the `yaml` package (trailing comments, quotes, brace globs, every list form), runs the checker on trees with broken bold skill names, mismatched Codex policy files and invalid frontmatter, regenerates the `server.ts` tables and policy files in a throwaway tree (including a deleted skill's leftover policy file), and fails when this repository's generated files are out of date (`node scripts/sync-server-skills.mjs --check`). The script tests run from directories with spaces in their paths. `scripts/skill-scripts.test.mjs` also runs every shell test shipped inside a skill (`skills/*/scripts/<name>.test.sh` against `<name>.sh`), so the one command covers them.
