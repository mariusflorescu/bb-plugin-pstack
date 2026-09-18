---
name: setup-pstack
description: "Choose which models pstack uses per role, discovered from what the running harness actually offers, and record it through that harness's own configuration when one exists. Use for /setup-pstack, \"configure pstack models\", or changing pstack's model choices."
---

# Setup pstack

Work out which models this session can actually delegate to, let the user pick one per pstack role, and record the choices through the host's real configuration mechanism, if it has one. No model name is hardcoded here on purpose: the available models and the storage mechanism differ between providers and harnesses.

## Steps

### 1. Find the harness's own model mechanisms first

Before inventing anything, use what the host already exposes.

On a BB host:

- **Catalog.** `bb provider list` lists every provider this host has — `pi`,
  `codex`, the `acp-*` agents, `muse`, and anything else installed — so enumerate
  all of them, not just the one this thread runs on. `bb provider models
  <providerId>` lists that provider's models; add `--json` to get each model's
  real `supportedReasoningEfforts` and `defaultReasoningEffort`, which the
  default table view omits. Both commands take `--environment <id>` or
  `--machine <id-or-name>`: use the workspace you are actually spawning into,
  because some providers scope their model list per workspace and the answer can
  differ from the host default.
- **Per-spawn choice, not a stored role table.** BB keeps one remembered
  provider/model pair per project — what a new thread gets when the flags are
  omitted — and applies a model per spawn:
  `bb thread spawn --provider <id> --model <id> --reasoning-level <level>`.
  There is no per-role model record, no per-role model map, and no CLI that
  reads or writes one. Do not hunt for one, and do not write a file expecting
  BB to load it as configuration.
- **What that means for role intent.** The mapping you settle on here is intent
  you honor by passing explicit flags when you spawn workers, not a setting BB
  stores and re-applies on its own.

On another host, discover the equivalent: a model catalog the session can query, and a configuration file or setting the harness reads. If no catalog and no config authority exist, do not fabricate one.

### 2. Discover the available models

Get the real catalog of models this session can run or delegate to. Prefer a models API, config file, or CLI the harness exposes for the current session. If you can only discover identifiers by trying, do not guess. If you cannot discover any, say so and ask the user to paste the identifiers they have access to.

Never invent or assume a model. Do not carry over the upstream author's slugs (`grok-4.6-fast-xhigh`, `claude-fable-5-1-thinking-max`, and similar): they are unrelated to whatever the user actually has.

Inheriting the parent model is a valid choice only where the harness supports it, and omission does not imply inheritance. On a BB host, omitting `--model` from `bb thread spawn` falls back to the project's remembered provider/model, not the parent thread's model, so a pstack fan-out cannot inherit that way. The one place BB does inherit is a workflow worker: an agent call with no explicit selection inherits the run's origin provider, model, and reasoning level. Treat inherit-the-parent as valid only where you have confirmed it; otherwise leave it out.

### 3. Map and confirm

Show every pstack role with its current choice, marking any value not in the discovered set as needing a choice. Ask whether to accept as-is or change specific roles, offering only discovered models plus an inherit-the-parent option where it is valid. Prefer the harness's structured question tool when it has one; otherwise ask in plain text.

Define the roles as you map them; none of the following behaviours are host-native unless the host says so:

- The **fan-out** of panel roles (arena runners, architect runners, interrogate reviewers) is pstack's own: one subagent per list entry, so the list length sets the count. Record it as the user's intent, not as a harness guarantee.
- `arena cross-judge pool` is a pool from which the arena picks one value whose family differs from the parent's when it can.
- `swarm workers` is the default model for every worker unless a race assigns another per arm.
- Diversity across a panel is optional and bounded by real eligible choices. Do not require a fixed set of model families, and do not invent a paid model to create diversity.

### 4. Validate

Every chosen model must be in the discovered set, or be a valid inherit-the-parent choice. If a chosen model is not available, stop and ask again. Never write a slug you have not confirmed is available on this host.

pstack roles, with the upstream defaults as labels only:

```
feature, refactoring
bug-fix
perf-issue
hillclimb
judgment and prose
hardest tasks
how explorer
how explainer
why investigators
why synthesizer
reflect tooling
reflect judgment, divergent, synthesizer
arena runners                 (list)
arena cross-judge pool        (list, families should differ)
swarm workers
architect runners             (list)
interrogate reviewers         (list)
```

### 5. Record the choices through the host's mechanism

Write the choices to the configuration authority the running harness actually provides. Choose per host:

- **BB host.** Write nothing on the user's behalf. BB has no configuration
  authority for a per-role model table, and its only persisted execution state is
  the single remembered project provider/model pair, which is a default for new
  threads rather than a role map. Confirm the mapping, then either (a) hand it
  back for the user to keep in context, to apply when you spawn workers with
  explicit `--provider`, `--model`, and `--reasoning-level` flags, or (b) if the
  user wants it to persist, offer to save it where the project already keeps
  instructions (`.bb/AGENTS.md` or a project skill) and say plainly that agents
  read it as guidance — never that BB loads it as configuration.
- **Another harness.** If it has a settings or skills directory the harness reads, write a config file there in the shape it expects. If it has none, do not fabricate a portable file and do not claim it will load elsewhere. Present the mapping in the reply for the user to keep and say it is not auto-loaded.

Write only discovered values (or a valid inherit-the-parent choice), and keep the write idempotent.

### 6. Confirm, and state the scope honestly

Tell the user:

- Where the choices were recorded, and whether that host treats them as advisory or authoritative.
- What that host does with them (this harness loads them for new sessions or threads; another harness will not).
- That this configuration is host-specific and claims no portability across harnesses.
- That a missing, unknown, or differing native capability was surfaced rather than silently substituted.

### 7. Offer a verification skill (optional)

Check whether the project has a way to drive the real app for proof (a `verify-*` skill, or an existing harness). If not, offer once: "want a project-local verification skill, so agents can drive the app the way a user does and prove changes work? I can generate one." On yes, invoke the local `create-verification-skill` skill if it is installed (it resolves wherever pstack lives: workspace, user, or plugin). On no, move on without pushing.

## Provenance and local adaptations

Adapted for this personal skill library from the pstack plugin, `cursor/plugins` at commit `889ec4b68fa5aab0e867dad71ec3fdf386ae48f3`, path `pstack/skills/setup-pstack/SKILL.md`. MIT, Copyright (c) 2026 Lauren Tan.

This copy is harness and provider agnostic. Model names, delegation APIs, transcript paths, question tools, config files, and hosting/secret mechanisms that were specific to the upstream author's environment are replaced with instructions to discover what the running harness actually offers. Where a needed capability is absent, the instruction says to surface that rather than silently substituting a paid or fabricated default. Upstream names appearing below inside examples or historical notes are inactive references, not instructions.
