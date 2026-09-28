# pstack for bb

pstack is an engineering skill library for coding agents. Lauren Tan ([poteto](https://x.com/poteto)) wrote it for Cursor. This plugin ships it to bb as 50 skills, adapted so every delegation runs as a bb child thread on the model you picked for that role.

## Install

```bash
bb plugin install git:https://github.com/mariusflorescu/bb-plugin-pstack
```

Settings, then Plugins, then pstack has a master switch and one switch per skill.

Requires bb 0.43 or newer.

## Get started

1. Run `/setup-pstack`. It reads the providers and models this host offers (`bb provider models`) and writes the plugin's `models` setting: one `role: provider / model @effort` line per pstack role.
2. Use `/poteto-mode` (`$poteto-mode` in a Codex thread) for anything that needs rigor. It picks one of 23 playbooks and runs the other skills as the steps need them.

A Codex thread runs every skill as `$<name>` where this README and the skills write `/<name>`.

## How it works on bb

The plugin injects the pstack delegation rules into every thread. They say that an explorer, reviewer, runner, worker or judge is a bb child thread (`bb thread spawn --parent-self`) with the provider, model and effort of its role, and that the provider's built-in subagent tool (Claude Code's Agent or Explore, Codex subagents) is never used for a pstack role. A panel role spawns one child per entry, so `/interrogate` can put Claude and GPT reviewers on the same diff. Children report back to the parent thread.

[BB-NATIVE.md](./BB-NATIVE.md) is the contract that maps every Cursor mechanism upstream uses to its bb equivalent. `node scripts/check-bb-native.mjs` enforces it (after `npm ci --ignore-scripts`).

Three skills carry a `pstack-` prefix to avoid clashing with common personal skills: `/pstack-arena`, `/pstack-tdd` and `/pstack-blast-radius`.

Three skills come from Cursor's `cursor-team-kit` plugin. Upstream pstack names the first two but doesn't bundle them. `/thermo-nuclear-code-quality-review` is a harsh one-pass maintainability review of the current branch. `deslop` strips AI code slop from the diff, and poteto-mode runs it before every commit. `what-did-i-get-done` sums up the commits you authored in a time range as a short status update. [MANIFEST.md](./MANIFEST.md) records where they came from.

## Staying current with upstream

A daily bb automation runs the project skill `.bb/skills/sync-upstream`. It 3-way merges upstream `pstack/` changes, and changes to the three skills bundled from `cursor-team-kit`, onto this repo (`scripts/sync-upstream.mjs`), translates anything Cursor-native per the contract, and opens one PR. It never merges. `UPSTREAM` holds the pinned upstream commit and one `bundle=` line per bundled skill.

## Credit

Adapted from [cursor/plugins pstack](https://github.com/cursor/plugins/tree/main/pstack) by [Lauren Tan](https://x.com/poteto), MIT, Copyright (c) 2026 Lauren Tan. The upstream README is kept verbatim in [UPSTREAM-README.md](./UPSTREAM-README.md), and [docs/guide/](./docs/guide/README.md) is upstream's guide adapted to bb. The bb packaging started from [wy3z/bb-plugin-pstack](https://github.com/wy3z/bb-plugin-pstack). [MANIFEST.md](./MANIFEST.md) records the provenance.

This plugin is not affiliated with Cursor or with the pstack author.

## License

MIT. [LICENSE](./LICENSE) keeps the upstream copyright notice.
