# Set up pstack

In this page you install the plugin, pick which models pstack uses, and run your first task. Setup is one command plus a short conversation.

## Install the plugin

Install pstack the way your harness supports. On a Cursor-based host that is:

```text
/add-plugin pstack
```

On another harness, install this library wherever that harness discovers skills (a project skills directory, or the user skills root). If you are reading this file, it is already installed somewhere the running harness can see.

## Pick your models

Run:

```text
/setup-pstack
```

[`/setup-pstack`](../../skills/setup-pstack/SKILL.md) discovers the models the running host actually offers (on a BB host, `bb provider models` lists them), shows you each role (code delegates, judgment, the review panels), and asks what you want. Answer the questions. It records the choices where that host keeps configuration. If the host has no per-role config mechanism, it hands you the mapping to keep, and says so instead of writing a file nothing reads.

You only override what you care about. A role with no recorded choice keeps the skill's default. To restore a default later, remove that role's entry, or just run `/setup-pstack` again.

If your host can inherit the parent model, set a role to inherit-the-parent and pstack omits the subagent model field, so the subagent inherits your parent chat model. For a panel role the value is a list, and one subagent runs per entry, so the list length sets the panel size. Setup also configures `swarm workers`, the default model for every `/swarm` worker unless a race names a model for each arm.

The choices apply to this host only. They are not auto-loaded by a different provider or harness; configure that host on its own terms.

## Accept the verification offer, or don't

At the end of setup, `/setup-pstack` looks for a way to prove app behavior in your project, either a `verify-*` skill or an existing harness. If it finds neither, it offers once to generate one with [`/create-verification-skill`](../../skills/create-verification-skill/SKILL.md).

Say yes and it writes the project-local `verify-<app>/` skill directory, a project-local skill that teaches agents to drive your app the way a user does. It proves the skill works once before handing it over. Say no and setup moves on. You can run `/create-verification-skill` yourself any time. [Verify and ship](./06-verify-and-ship.md#create-a-project-verification-skill) covers when it earns its place.

After setup, start a new chat. The model choices apply to new sessions on this host.

## Run your first task

Pick something real but small, and describe it the way you'd describe it to a colleague:

```text
/poteto-mode add a --json flag to this command. text output stays byte-identical. verify both.
```

Watch the todo list. Its first items are the matched playbook's steps copied in, the Feature playbook for this prompt. If `/poteto-mode` skips a step, the step stays in the list with `skip: <reason>`, so you can see what it chose not to do.

From here you can type normal follow-ups. `/poteto-mode` is sticky. It stays on for the conversation until you opt out by saying so.

Next: [Route work through `/poteto-mode`](./02-poteto-mode.md).
