# pstack for bb

pstack is an engineering skill library for coding agents. Lauren Tan ([poteto](https://x.com/poteto)) wrote it for Cursor. This plugin brings it to bb as 47 skills, each one a slash command available in every thread.

Start with `/poteto-mode`. It reads your request, picks one of 23 playbooks, and runs the other skills as the steps need them. The rest of the library is what those playbooks reach for:

- understanding: `/how`, `/why`, `/teach`, `/recall`, `/figure-it-out`
- design and review: `/architect`, `/interrogate`, `/pstack-arena`, `/pstack-blast-radius`, `/swarm`
- proof: `/create-verification-skill`, `/maintain-verification-skill`, `/pstack-tdd`
- prose and cleanup: `/unslop`, `/technical-writing`, `/no-comments`
- steering: 23 `principle-*` skills you can name by hand to redirect an agent mid-task

Most of these are user-invoked on purpose. They carry `disable-model-invocation`, so they stay out of the model prompt until you type the name. The model gets the context when you ask for it, not before.

## install

```bash
bb plugin install git:https://github.com/wy3z/bb-plugin-pstack
```

Then open Settings, then Plugins, then pstack. That page has a master switch and one switch per skill, so you can keep the set to the handful you actually use.

Requires bb 0.43 or newer.

## credit

Adapted from [cursor/plugins pstack](https://github.com/cursor/plugins/tree/main/pstack) by [Lauren Tan](https://x.com/poteto), MIT, Copyright (c) 2026 Lauren Tan. The author's own README is kept verbatim in [UPSTREAM-README.md](./UPSTREAM-README.md), and [docs/guide/](./docs/guide/README.md) follows the guide he wrote.

This plugin is an adaptation and is not affiliated with Cursor or with the pstack author.

## what changed from upstream

The skills used to name Cursor's tools, models, and config paths. They now describe what to look up in whichever harness runs them, and they say so when a harness lacks a capability instead of inventing a substitute.

bb specifics:

- `/setup-pstack` reads the catalog with `bb provider models`, then applies the choice per spawn. bb remembers one provider and model per project, so the per-role mapping is presented rather than stored.
- Parallel work uses `bb thread spawn`, then `bb thread wait` and `bb thread output` to drain it. A worker gets its own environment with `--new-environment worktree`.
- Loops and audit ticks use `bb automation create` instead of sleeping inside a thread.
- Evidence lookups use `bb memory` and any MCP servers you have connected.

Three skills are renamed to avoid clashing with personal skills installed here: `arena` is `/pstack-arena`, `tdd` is `/pstack-tdd`, and `blast-radius` is `/pstack-blast-radius`. Internal links point at the new names.

The benny automation pack ships as inactive reference files. Nothing is scheduled, and the pack needs a service it does not provide.

Every `SKILL.md` carries a provenance note naming the upstream file and commit it came from. [MANIFEST.md](./MANIFEST.md) records the pinned commit and each adaptation. [CAPABILITIES.md](./CAPABILITIES.md) lists what pstack expects from a host and what this plugin does not provide.

## license

MIT. [LICENSE](./LICENSE) keeps the upstream copyright notice.
