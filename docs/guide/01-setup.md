# Set up pstack

In this page you install the plugin, pick which models pstack uses, and run your first task. Setup is one command plus a short conversation.

## Install the plugin

In a terminal, run:

```bash
bb plugin install git:https://github.com/mariusflorescu/bb-plugin-pstack
```

bb asks you to confirm the install, then enables the plugin. **Settings**, then **Installed plugins**, then **pstack** has a master switch and one switch per skill.

## Pick your models

Run:

```text
/setup-pstack
```

[`/setup-pstack`](../../skills/setup-pstack/SKILL.md) detects the providers and models this bb host offers, asks for a reasoning budget, shows you each role (code delegates, judgment, the review panels), and asks what you want. Answer the questions. It writes the pstack plugin's `models` setting, one `role: provider / model @effort` line per role. bb injects that setting into every new thread as the pstack delegation rules, so each role a skill spawns runs as a bb child thread on the model you picked.

You only change what you care about. Setup starts from your current setting, or from the plugin default the first time, so a rerun keeps your earlier choices. You can also edit the **Role models** field on the plugin's settings page, or run `bb plugin config pstack set models`. To restore the defaults, run `bb plugin config pstack unset models`.

You might be wondering whether a role can follow whatever model the current thread runs. It can't. Every role names a provider, model, and effort, and pstack passes all three when it spawns that role's child thread. For a panel role the value is a list, and one child thread runs per entry, so the list length sets the panel size. Setup also configures `swarm workers`, the default model for every `/swarm` worker unless a race names a model for each arm.

## Accept the verification offer, or don't

At the end of setup, `/setup-pstack` looks for a way to prove app behavior in your project, either a `verify-*` skill or an existing harness. If it finds neither, it offers once to generate one with [`/create-verification-skill`](../../skills/create-verification-skill/SKILL.md).

Say yes and it writes `.bb/skills/verify-<app>/`, a project-local skill that teaches agents to drive your app the way a user does. It proves the skill works once before handing it over. Say no and setup moves on. You can run `/create-verification-skill` yourself any time. [Verify and ship](./06-verify-and-ship.md#create-a-project-verification-skill) covers when it earns its place.

After setup, start a new thread. bb builds a thread's instructions when its session starts, so the new setting reaches new threads, not ones already running.

## Run your first task

Pick something real but small, and describe it the way you'd describe it to a colleague:

```text
/poteto-mode add a --json flag to this command. text output stays byte-identical. verify both.
```

Watch the todo list. Its first items are the matched playbook's steps copied in, the Feature playbook for this prompt. If `/poteto-mode` skips a step, the step stays in the list with `skip: <reason>`, so you can see what it chose not to do.

From here you can type normal follow-ups. `/poteto-mode` is sticky. It stays on for the conversation until you opt out by saying so.

Next: [Route work through `/poteto-mode`](./02-poteto-mode.md).
