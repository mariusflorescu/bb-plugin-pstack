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

The active transcript is this thread's BB log. Reviewers read it themselves, so hand them the thread ID (`$BB_THREAD_ID`), not a copy.

```bash
bb thread log "$BB_THREAD_ID" --format verbose --all
```

`verbose` keeps every tool call and its output. Children this thread spawned keep their own logs (`bb thread list --parent-thread "$BB_THREAD_ID"`), and their reports already sit in this thread's log. Read only this thread and its children. Do not use `bb thread search` or open other projects' threads. That crosses project boundaries and reads private chats from unrelated work.

If the log does not load, write a tight digest of the session and pass that instead.

### 2. Spawn three reviewers in parallel

Spawn three child threads at once, one per lens, with `bb thread spawn --parent-self` and the provider, model and effort of the lens's role line in the pstack delegation rules. Write each brief to `$BB_THREAD_STORAGE/reflect/<lens>.md` and pass it with `--prompt-file`. Reviewers look up context the transcript references (tickets, chat threads, observability traces) through their MCP tools. Each template already tells them not to modify files.

| Lens | Role line | Prompt template |
|---|---|---|
| Judgment | `reflect judgment, divergent, synthesizer` | `references/judgment-reviewer.md` |
| Tooling | `reflect tooling` | `references/tooling-reviewer.md` |
| Divergent | `reflect judgment, divergent, synthesizer` | `references/divergent-reviewer.md` |

Pass each template verbatim, substituting the thread ID or digest where marked. Each reviewer's findings are its final message. Collect all three in one background command with `bb thread wait <id>` then `bb thread output <id>`.

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

A routing may name a skill without a path. `bb skill list --json` maps each name to its `filePath`. For a plugin skill that path is a runtime copy, so edit the plugin's source instead.

If your environment ships a SKILL.md validator, run it on every touched skill before declaring done. Skip this step if it doesn't.

### 6. Summarize for the user

Short list, no preamble:

- Edits applied: `<skill path>`. What changed, one line each.
- New skills created: `<skill path>`. One line each (rare).
- Backlog filed to the devex tracker: `<issue title>` (`<tags>`). One line each.
- Dropped: one line per rejected finding + reason from the synthesizer.
