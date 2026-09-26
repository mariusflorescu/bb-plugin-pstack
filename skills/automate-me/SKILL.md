---
name: automate-me
description: "Use for \"automate me\", \"create/update/refresh my -mode skill\", \"turn/capture my preferences or working style into a skill\", or wanting agents to follow how the user works. Drafts or revises a personal -mode skill via skill-creator + unslop, optionally pulling fresh evidence from recent transcripts."
disable-model-invocation: true
---

# Automate me

A guided flow for turning the user's working conventions into a skill agents will follow. The output is one `-mode` skill tailored to them (e.g. `jay-mode`, `priya-mode`).

This skill orchestrates three others: an inline mining pass (see step 1), the `skill-creator` skill (authoring), and the **unslop** skill (prose discipline). It sequences them. It doesn't replace them.

## Flow

### 0. Check for an existing skill

Run `bb skill list --environment "$BB_ENVIRONMENT_ID" --json` and look for a `<handle>-mode` entry (`<plugin>:<handle>-mode` in a provider plugin). It covers project skills (`.bb/skills/<name>/SKILL.md`), user skills (`~/.bb/skills/<name>/SKILL.md`), BB and provider plugin skills, and each provider's own skill folders, and each entry's `filePath` says where the skill lives. If one exists, ask the user to confirm intent (unless they already said "update my skill" or similar):

- Update the existing skill (default for repeat runs)
- Start fresh (rare, ask why before doing it)

A `scope` `plugin` skill is a file its plugin installed, so find its source before you edit it. Classify it by its record's `provider` field first, as BB does. A skill whose `provider` is null belongs to a BB plugin: read `bb plugin source <plugin-id> --json`. A `path:` source is the plugin's own checkout, so edit it there. A `git:` or `npm:` source is an install cache that the next update replaces, so edit the repository or package it names. A `builtin:` plugin ships with BB and cannot be edited. A skill whose `provider` is set comes from that provider's own plugin, even when its `pluginId` matches a BB plugin's; `bb plugin source` does not know it, and its skills are named `<pluginId>:<skill>`. The record's `provider` installed it from a marketplace into its own cache (`plugins/cache/<marketplace>/<plugin>/<version>/` in the `filePath`), which the provider's next plugin update replaces. `claude plugin marketplace list --json` (provider `claude-code`) or `codex plugin marketplace list --json` (provider `codex`) names that marketplace's source, and the plugin's entry in the marketplace's manifest says where in it, or in which other repository, the plugin lives. Edit it there. When the source is `builtin:` or the user does not maintain what it names, offer a `<handle>-mode` user or project skill instead. A user or project skill overrides a BB plugin skill of the same name. A provider plugin skill keeps loading in its provider, so the new skill sits beside it and does not replace it.

Update mode changes the rest of the flow:
- Step 1 mines only history since the skill was last edited (`git log -1 --format=%ct <path>` on the file in its source, epoch seconds).
- Step 2 asks what's changed or missing, not what to capture from zero.
- Step 4 edits the existing file in place, in the plugin's source for a plugin skill. Preserve sections the user hasn't contradicted. Revise ones with new evidence. Add new sections only for genuinely new rules.

### 1. Mine their history

Scope the history before fanning out. Use only the current project (`$BB_PROJECT_ID`). Don't read other projects' threads. That crosses project boundaries and reads private chats from unrelated projects. `../recall/scripts/project-threads.sh <days>` lists its threads updated in the last `<days>` days, hidden and archived ones included, newest first.

Survey recent agent conversations within that scope for recurring patterns. Spawn parallel child threads on your `swarm workers` model, per the pstack delegation rules, across slices of history (e.g. last 2-4 weeks, split by the `updated` column into 3 slices so each has enough material). Each slice's brief names its thread IDs and the window's start in epoch seconds (now minus the window, or the skill's last edit in update mode). The child reads each thread's raw events within the window, dropping streamed deltas, which the completed items repeat:

```bash
bb thread log <id> --format json --all | jq --argjson since <start> '[.[] | select(.createdAt >= $since * 1000 and (.type | test("[Dd]elta$") | not))]' > "$BB_THREAD_STORAGE/<id>.json"
```

Not the timeline formats (`--format verbose`): after a `bb thread clear` they start at the clear, and the conversations before it in the window disappear. The user's follow-up turns (`client/turn/requested` events) carry most corrections and stated preferences. The child looks for the signals below and returns a short structured list of patterns it saw with evidence pointers (`@thread:<id>`). Default signals worth hunting:

- Response preferences (length, tone, format, "dumb it down" corrections)
- Delegation habits (subagents, models, specialized workflows, parallelism)
- Verification posture (what "done" means, unit tests vs live repro, reviewers)
- Code and prose discipline (style, principles cited, lint/format tools)
- Process conventions (worktrees, commits, PRs, review/merge tooling)
- Meta preferences (fixing skills mid-task, proposing new ones)

Cross-check across slices before elevating a signal. Patterns seen in 2+ slices are high-confidence. Lone signals are weak and usually get dropped.

### 2. Ask the user directly

Mining misses intent that hasn't come up yet. Ask the user structured multi-choice questions rather than asking them to type from scratch.

Shape: one or two questions with 3-4 options each, multi-select for category questions. Start broad ("Which areas matter most?"), then follow up on selected areas with specific options. After the structured rounds, one free-form chat question catches anything the options missed.

Don't dump 20 questions.

### 3. Cluster findings

Group the combined signals into sections. Common ones (use only what applies):

- **Response style**: length, tone, format.
- **Autonomy**: how much to do without asking, MCP tool use.
- **Understand first**: which skills to reach for when scoping or investigating a change.
- **Subagents**: default, parallelism, model-to-task, specialized workflows.
- **Prose / code discipline**: principles, lint tools, style guides.
- **Review and verify**: repro posture, verification skills, live-testing tools.
- **Process**: git worktrees, commits, PRs, review/merge tooling.
- **Skills**: skill-authoring habits, fix-the-skill-first, proposing new skills.

The **poteto-mode** skill shows the shape. Read it for granularity. Don't copy its content. The user's rules are not the same as poteto-mode's.

### 4. Draft the skill

Use the `skill-creator` skill to author the skill. Placement:

- Path: keep an existing mode skill where it lives, in the source step 0 found for a plugin skill. For a new mode, default to `.bb/skills/<handle>-mode/SKILL.md` in the project (or `~/.bb/skills/<handle>-mode/SKILL.md` if the user prefers a personal skill).
- Handle: the user's first name or chosen identifier.
- Frontmatter `description`: trigger on their name + `/<handle>-mode` + "work in their style", not on generic keywords like "write code" or "review PR".
- Frontmatter formatting: follow `skill-creator`'s frontmatter contract. Keep `description` as one YAML scalar. Quote it or use `description: >-` with indented continuation lines when punctuation or wrapping requires it.
- Frontmatter `disable-model-invocation: true` by default. Opt out only if the user explicitly wants their mode to apply on every turn.

### 5. Iterate on prose

Apply the **unslop** skill and `skill-creator`'s writing guidelines to every line.

Show the draft to the user and take feedback. Expect multiple iterations. Cut ruthlessly. A mode skill is not a manual.

### 6. Land it

For a project skill, work in a worktree off main. Commit and open a PR. Don't push to main directly. A plugin skill lands the same way, in the repository its source names. A user skill in `~/.bb/skills/` sits outside the repo, so write it in place.

## Guardrails

- **Don't overfit to one conversation.** A preference stated once and contradicted another time is noise. Require multiple instances before codifying it.
- **Don't be clever.** Restating other skills' contents, inventing metaphors, or writing "poetic" prose for an agent reader is cost without benefit. Keep it operational.
- **Reference, don't inline.** Other skills the user relies on should appear as path references, not pasted excerpts. Same for any principle docs they maintain elsewhere.
- **Keep sections minimal.** Only add a section if the user has a specific, non-default rule there. "Communicate clearly" is not a section. "Short paragraphs. Tables when comparing options. Bullets only when items are genuinely parallel." is.
- **Name conventions generic.** Use "the user" or "the human" in imperatives, not the author's first name.
- **Don't force symmetry.** If a user has no process rules worth writing down, skip the Process section entirely.

## Evaluation

A `-mode` skill is subjective output. `skill-creator`'s fresh-thread evaluation loop isn't useful here. Vibe-check with the user: does it read like them? Did it miss anything? Then ship.

Run a description-optimization loop only if the skill's trigger accuracy turns out to be a problem in practice.

## When not to use

- User wants a task-specific skill (not working conventions): `skill-creator` alone, no mining required.
- User wants to capture one narrow workflow (e.g. "how I write commit messages"). That's a regular skill, not a mode skill.

