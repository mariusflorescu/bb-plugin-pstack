---
name: setup-pstack
description: Configure which models pstack uses per role and at what reasoning budget. Detects the providers and models this BB host offers and writes the pstack plugin's models setting, which every new thread receives as the pstack delegation rules. Use for /setup-pstack, "configure pstack models", "pstack budget", or changing pstack's model choices.
---

# Setup pstack

Write the pstack plugin's `models` setting. BB injects it into every new thread as the pstack delegation rules, so each pstack role spawns its BB child thread with the provider, model and reasoning effort chosen here.

## Steps

### 1. Detect available models

Run `bb provider list`, then `bb provider models <provider> --environment "$BB_ENVIRONMENT_ID" --json` for every provider it lists. Each model carries its `id`, its `supportedReasoningEfforts` and its `defaultReasoningEffort`. The environment flag matters because some providers scope their model list per workspace. A provider whose command fails or returns no models is unavailable; say so and leave it out. That catalog is the only source. Never write a provider, model or effort you have not seen in it.

### 2. Load current state

Run `bb plugin config pstack --json` and read the `models` value. When it is unset, the current state is the plugin default the same command shows. A line whose role is not in step 5, such as `how critics`, is from a retired role. Drop it. A `# budget:` line records the last budget.

### 3. Budget, map, and confirm

**(a) Ask for a budget.** Ask the user with these four options and these exact labels, and name the current budget when the setting records one.

- `unlimited: keep max`
- `large: xhigh reasoning`
- `medium: high reasoning`
- `small: medium reasoning`

**(b) Apply it.** Start from the current state. `unlimited` leaves every effort as it is. `large`, `medium` and `small` set the effort of every entry, panel entries included, to `xhigh`, `high` or `medium`. When a model does not support that effort, use its highest supported effort at or below the target from step 1.

**(c) Show the roles and confirm.** Show every role with its `provider / model @effort`, marking any entry not in the detected catalog as needing a choice. Also list each line step 2 dropped. Ask whether to accept as-is or change specific roles, offering the detected `provider / model` pairs. For panel roles (arena runners, architect runners, interrogate reviewers) the value is a comma-separated list, and one child thread runs per entry, so the list length sets the count. `arena cross-judge pool` is also a list, but the arena (and show-me-your-work's cross-model reviewer) takes the first entry whose model family differs from the parent thread's. Offer at least one entry from a second family when the catalog has one. `swarm workers` is the default model for every worker unless a race assigns another model per arm.

### 4. Validate

Every entry's provider must be in `bb provider list`, its model in that provider's catalog, and its effort in that model's `supportedReasoningEfforts`. If one fails, stop and ask again.

### 5. Write the setting

Write the whole value in one call so re-runs stay idempotent. Put it in a file first, since it is multi-line:

```
bb plugin config pstack set models "$(cat "$BB_THREAD_STORAGE/pstack-models.txt")"
```

One line per role, using the same role names poteto-mode uses, in this shape:

```
# budget: large (xhigh)
feature, refactoring: claude-code / claude-opus-5-5 @xhigh
bug-fix: claude-code / claude-fable-5-1 @xhigh
perf-issue: claude-code / claude-fable-5-1 @xhigh
hillclimb: claude-code / claude-fable-5-1 @xhigh
judgment and prose: claude-code / claude-opus-5-5 @xhigh
hardest tasks: claude-code / claude-fable-5-1 @xhigh
how explorer: codex / gpt-6-luna @high
how explainer: claude-code / claude-opus-5-5 @xhigh
why investigators: codex / gpt-6-luna @high
why synthesizer: claude-code / claude-opus-5-5 @xhigh
reflect tooling: claude-code / claude-opus-5-5 @xhigh
reflect judgment, divergent, synthesizer: claude-code / claude-fable-5-1 @xhigh
arena runners: claude-code / claude-opus-5-5 @xhigh, claude-code / claude-fable-5-1 @xhigh, codex / gpt-6-astra @xhigh, codex / gpt-6-sol @xhigh
arena cross-judge pool: codex / gpt-6-astra @xhigh, claude-code / claude-fable-5-1 @xhigh
swarm workers: claude-code / claude-opus-5-5 @high
architect runners: claude-code / claude-opus-5-5 @xhigh, claude-code / claude-fable-5-1 @xhigh, codex / gpt-6-astra @xhigh, codex / gpt-6-sol @xhigh
interrogate reviewers: claude-code / claude-opus-5-5 @xhigh, claude-code / claude-fable-5-1 @xhigh, codex / gpt-6-astra @xhigh, codex / gpt-6-sol @xhigh
```

Read it back with `bb plugin config pstack --json` and confirm the value matches the file.

### 6. Confirm

Tell the user the setting was written. BB builds a thread's instructions when its provider session starts, so the new mapping applies to new threads, not to threads already running. Re-running this skill updates it. `bb plugin config pstack unset models` returns to the plugin default.

### 7. Offer a verification skill (optional)

Check whether the project has a way to drive the real app for proof (a verification skill under `.bb/skills/`, or an existing harness). If not, offer once: "want a project-local verification skill, so agents can drive the app the way a user does and prove changes work? I can generate one with /create-verification-skill." On yes, invoke `/create-verification-skill`. On no, move on without pushing.
