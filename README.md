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

## poteto-mode stays on in its thread

To turn poteto-mode on for a thread, start its first message with `/poteto-mode` (`$poteto-mode` in a Codex thread). The thread's standing instructions then carry a short note that tells the agent to track its playbook's steps in a task list and finish every one. The thread header shows a **poteto-mode** chip.

BB builds those instructions with the thread's session, at the first message and again at any later rebuild, such as a BB restart. So a switch in the middle of a thread takes effect at the next rebuild. To opt out, click the chip, which then reads **poteto-mode off**. To stop poteto-mode before the next rebuild, tell the agent to stop it. To turn the mode back on, click the chip again or type `/poteto-mode` in a later message.

## How it works on bb

The plugin injects the pstack delegation rules into every thread. They say that an explorer, reviewer, runner, worker or judge is a bb child thread (`bb thread spawn --parent-self`) with the provider, model and effort of its role, and that the provider's built-in subagent tool (Claude Code's Agent or Explore, Codex subagents) is never used for a pstack role. A panel role spawns one child per entry, so `/interrogate` can put Claude and GPT reviewers on the same diff. Children report back to the parent thread.

Task leads (threads with no parent) always delegate meaningful work or independent verification to new BB child threads, including small tasks and investigations, and coordinate through `bb thread tell`. Spawning and messaging task-related threads need no further permission. Children complete their assignment and report back. Each child brief names the roles it may spawn or says "Do not spawn"; the assigned work's other gates still apply.

The [BB collaboration instructions](./docs/bb-collaboration-instructions.md) preserve BB guide's introduction and replace its restrictive thread bullet with positive guidance to spawn and message task-related threads. BB guide exposes only an on/off setting for the bundled introduction, so put the customized introduction in the Custom instructions plugin, preserving any existing custom instructions, and turn off only BB guide's `introduction` setting. Keep its skills enabled. New sessions receive the updated instructions. Review the customized introduction when BB changes its CLI guidance.

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
