---
name: reflect
description: Spawn three parallel review subagents over the active transcript, surface learnings, and route each to a concrete edit on an existing skill. Use when the user says reflect.
disable-model-invocation: true
---

# Reflect

Mine the current conversation for durable learnings, then route them into skill edits.

## When to invoke

Invoke when the user says "reflect" or "/reflect". Skip when the conversation is trivial, off-topic, or already covered by an existing skill the parent followed correctly. One-offs are not learnings.

## Process

### 1. Locate the active transcript

The active transcript is the current conversation in this thread's BB log. A `bb thread clear`, or the provider resetting its conversation, starts a new conversation in the same thread, and the log keeps the earlier ones. Reviewers read the log themselves, so hand them the thread ID (`$BB_THREAD_ID`) and the event sequence the current conversation starts after, not a copy. Children this thread spawned keep their own logs, and so do the children they spawned. List the ones the current conversation delegated to, at every depth, now, before step 2 makes the reviewers children too. From this skill's directory:

```bash
../show-me-your-work/scripts/run-start.sh
../show-me-your-work/scripts/descendants.sh "$BB_THREAD_ID" <seq>
```

The first prints that sequence, `0` when the thread was never cleared. Pass it to the second as `<seq>`. The second prints one `thread<TAB>parent<TAB>after-seq<TAB>title` line per descendant, hidden ones included, and nothing when there are none. A clear keeps the children of earlier conversations, so it lists a child only if the current conversation made it (after-seq `0`) or messaged it with `bb thread tell` (after-seq just before the first such message), and it looks under each listed child the same way, from when that child's part began. The transcript is this thread's events after that sequence plus each listed descendant's events after its after-seq. Do not use `bb thread search` or open any other thread. That reads private chats from unrelated work.

If the log does not load, write a tight digest of the session and pass that instead.

### 2. Spawn three reviewers in parallel

Spawn three child threads at once, one per lens, with `bb thread spawn --parent-self` and the provider, model and effort of the lens's role line in the pstack delegation rules. Write each brief to `$BB_THREAD_STORAGE/reflect/<lens>.md` and pass it with `--prompt-file`. Reviewers look up context the transcript references (tickets, chat threads, observability traces) through their MCP tools. Each template already tells them not to modify files.

| Lens | Role line | Prompt template |
|---|---|---|
| Judgment | `reflect judgment, divergent, synthesizer` | `references/judgment-reviewer.md` |
| Tooling | `reflect tooling` | `references/tooling-reviewer.md` |
| Divergent | `reflect judgment, divergent, synthesizer` | `references/divergent-reviewer.md` |

Pass each template verbatim, substituting the thread ID, the start sequence and the descendant lines from step 1 (or `none`), or the digest where marked. Each reviewer's findings are its final message. Collect all three in one background command with `bb thread wait <id>` then `bb thread output <id>`.

### 3. Synthesize

Spawn one child thread on your `reflect judgment, divergent, synthesizer` model the same way. Its brief is `references/synthesizer.md` verbatim, with each reviewer's `bb thread output` inlined where marked. The synthesizer spot-verifies citations, which can require MCP access. It returns a structured Accepted / Rejected / Backlog list as its final message. Collect it with `bb thread wait` then `bb thread output`.

### 4. Structural enforcement check

Sanity-check the synthesizer's Accepted list. For any item that would be enforced more reliably by a lint rule, script, metadata flag, or runtime check, move it from Accepted to Backlog. See the **encode-lessons-in-structure** principle skill.

### 5. Apply

Before applying any Accepted edit, present the synthesizer's full Accepted/Rejected/Backlog output to the user and wait for explicit approval. The user picks which subset to apply and may redirect routings. Skill changes affect every future agent in the org. Do not auto-apply.

Backlog items file to whatever devex / backlog tracker your team uses automatically. Only the Accepted list waits for approval.

For each approved Accepted item, follow the Routing field exactly:

- Trivial existing-skill edit (a one-line bullet, a tightened sentence, a stale fact corrected): parent does directly.
- Substantive existing-skill edit (a new section, a new pattern table, more than ~10 lines): hand to the `skill-creator` skill and run its verify and fresh-thread evaluation loop.
- `tune description: <skill path>` (the skill exists but didn't trigger when it should have): hand to `skill-creator` and run its trigger check with near-miss prompts.
- `new skill via skill-creator: <kebab-name>`: hand creation to `skill-creator`. Do not invent the shape ad hoc.

A routing may name a skill without a path. `bb skill list --environment "$BB_ENVIRONMENT_ID" --json` maps each name to its `filePath` in this workspace. A `scope` `plugin` skill is a file its plugin installed, so find its source before you edit it. A `pluginId` that `bb plugin list --json` lists is a BB plugin: read `bb plugin source <plugin-id> --json`. A `path:` source is the plugin's own checkout, so edit it there. A `git:` or `npm:` source is an install cache that the next update replaces, so edit the repository or package it names. A `builtin:` plugin ships with BB and cannot be edited. Any other `pluginId` is a provider plugin, which `bb plugin source` does not know, and its skills are named `<pluginId>:<skill>`. The record's `provider` installed it from a marketplace into its own cache (`plugins/cache/<marketplace>/<plugin>/<version>/` in the `filePath`), which the provider's next plugin update replaces. `claude plugin marketplace list --json` (provider `claude-code`) or `codex plugin marketplace list --json` (provider `codex`) names that marketplace's source, and the plugin's entry in the marketplace's manifest says where in it, or in which other repository, the plugin lives. Edit it there. When the source is `builtin:` or the user does not maintain what it names, offer a user or project skill that carries the change instead, or send the change to Backlog. A user or project skill overrides a BB plugin skill of the same name. A provider plugin skill keeps loading in its provider, so the new skill sits beside it and does not replace it.

If your environment ships a SKILL.md validator, run it on every touched skill before declaring done. Skip this step if it doesn't.

### 6. Summarize for the user

Short list, no preamble:

- Edits applied: `<skill path>`. What changed, one line each.
- New skills created: `<skill path>`. One line each (rare).
- Backlog filed to the devex tracker: `<issue title>` (`<tags>`). One line each.
- Dropped: one line per rejected finding + reason from the synthesizer.
