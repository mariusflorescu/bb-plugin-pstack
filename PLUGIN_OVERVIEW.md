## Getting started

Install the plugin, then run `/setup-pstack`. It reads the providers and models this host offers and writes one `provider / model @effort` per pstack role into the plugin's `models` setting. After that, `/poteto-mode` is the way in.

## What you get

47 skills from pstack, available in every thread. `/poteto-mode` reads your request, picks one of 23 playbooks, and runs the other skills the playbook needs.

- `/how`, `/why`, `/teach` and `/recall` answer questions about code before you edit it.
- `/architect`, `/interrogate`, `/swarm` and `/pstack-arena` shape a change and put more than one model on it.
- `/pstack-blast-radius` looks for what the change breaks outside its own diff.
- `/create-verification-skill` and `/maintain-verification-skill` keep a project's proof current.
- `/pstack-tdd` writes the failing test first.
- `/unslop`, `/technical-writing` and `/no-comments` clean prose and comments.
- 23 `principle-*` skills name the rule you want an agent to follow, mid-task.

## How it works

Every thread receives the pstack delegation rules: each explorer, reviewer, runner or worker is a bb child thread on the provider, model and effort you chose for its role, never the provider's built-in subagent tool. Panels mix providers, so a Claude thread can get a GPT reviewer and the other way round.

Most skills are user-invoked (`disable-model-invocation`, plus `agents/openai.yaml` for Codex), so they cost no context until you run one: `/<name>` in a Claude Code thread, `$<name>` in a Codex thread. typescript-best-practices loads itself for `.ts` and `.tsx` files. Settings shows a master switch and one switch per skill.

## Requirements

bb 0.43 or newer. The orchestration scripts under `poteto-mode/scripts` need Bun, and PR watching needs `gh`.

## Credit

pstack is Lauren Tan's work: [cursor/plugins](https://github.com/cursor/plugins/tree/main/pstack), MIT, Copyright (c) 2026 Lauren Tan. The bb adaptations are recorded in [BB-NATIVE.md](https://github.com/mariusflorescu/bb-plugin-pstack/blob/main/BB-NATIVE.md).
