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

The parent locates the active conversation transcript before fanning out. Prefer a native read of the active conversation. If transcripts are only on disk, use the harness's documented transcript directory for the active workspace only, and never glob across unrelated project directories.

```bash
# Set <transcript-dir> to the harness's documented active-workspace transcript directory.
ls -t <transcript-dir>/*.jsonl <transcript-dir>/*/*.jsonl <transcript-dir>/*/subagents/*.jsonl 2>/dev/null | head -10
```

Three transcript layouts: legacy flat (`<id>.jsonl`), current nested (`<id>/<id>.jsonl`), and subagent (`<parent>/subagents/<child>.jsonl`).

For each candidate, read the first JSONL line and check that `message.content[0].text` contains the conversation's opening user prompt. Take the matching path. If no path resolves, write a tight digest of the session and pass that instead.

### 2. Spawn three reviewers in parallel

If the harness has native delegation, issue the three delegations in one message, each with an explicit model and a mode that keeps MCP/tool access available. Confirm the capability against the harness's real delegation mechanism before falling back. Only when it genuinely has none, run the three lenses sequentially in this session, one after another, and say that the reviewers did not run independently. Reviewers need MCP access for context lookups (tickets, chat threads, observability traces referenced in the transcript); a read-only or ask mode strips that access.

| Lens | `model` | Prompt template |
|---|---|---|
| Judgment | your configured reflect-judgment model (discover the session's strongest judgment model) | `references/judgment-reviewer.md` |
| Tooling | your configured reflect-tooling model (discover the session's strongest tooling/judgment model) | `references/tooling-reviewer.md` |
| Divergent | your configured reflect-judgment model (discover the session's strongest judgment model) | `references/divergent-reviewer.md` |

Pass each template verbatim, substituting the transcript path or digest where marked. Collect each lens's findings from its delegation response, or inline when run sequentially.

### 3. Synthesize

Delegate one synthesizer on your configured reflect-judgment model (otherwise the strongest judgment model available), in a mode that keeps MCP/tool access available; if the harness has no delegation, do the synthesis in this session and say so. The synthesizer's quality check includes spot-verifying citations, which can require MCP access; a read-only mode strips that access. Use `references/synthesizer.md` verbatim, with each reviewer's full output inlined where marked. The synthesizer returns a structured Accepted / Rejected / Backlog list.

### 4. Structural enforcement check

Sanity-check the synthesizer's Accepted list. For any item that would be enforced more reliably by a lint rule, script, metadata flag, or runtime check, move it from Accepted to Backlog. See the **encode-lessons-in-structure** principle skill.

### 5. Apply

Before applying any Accepted edit, present the synthesizer's full Accepted/Rejected/Backlog output to the user and wait for explicit approval. The user picks which subset to apply and may redirect routings. Skill changes affect every future agent in the org. Do not auto-apply.

File Backlog items to the team's tracker only when one is configured and the user has authorized posting. Otherwise list them for the user to file. Nothing is posted automatically.

For each approved Accepted item, follow the Routing field exactly:

- Trivial existing-skill edit (a one-line bullet, a tightened sentence, a stale fact corrected): parent does directly.
- Substantive existing-skill edit (a new section, a new pattern table, more than ~10 lines): hand to the discovered skill-authoring skill (the `skill-creator` skill when installed) and run its draft / test / iterate loop.
- `tune description: <skill path>` (the skill exists but didn't trigger when it should have): hand to the skill-authoring skill and run its description-optimization loop.
- `new skill via <kebab-name>`: hand creation to the discovered skill-authoring skill, or draft it directly when none is installed. Do not invent the shape ad hoc.

If your environment ships a SKILL.md validator, run it on every touched skill before declaring done. Skip this step if it doesn't.

### 6. Summarize for the user

Short list, no preamble:

- Edits applied: `<skill path>`. What changed, one line each.
- New skills created: `<skill path>`. One line each (rare).
- Backlog filed to the devex tracker: `<issue title>` (`<tags>`). One line each.
- Dropped: one line per rejected finding + reason from the synthesizer.

## Provenance and local adaptations

Adapted for this personal skill library from the pstack plugin, `cursor/plugins` at commit `889ec4b68fa5aab0e867dad71ec3fdf386ae48f3`, path `pstack/skills/reflect/SKILL.md`. MIT, Copyright (c) 2026 Lauren Tan.

This copy is harness and provider agnostic. Model names, delegation APIs, transcript paths, question tools, config files, and hosting/secret mechanisms that were specific to the upstream author's environment are replaced with instructions to discover what the running harness actually offers. Where a needed capability is absent, the instruction says to surface that rather than silently substituting a paid or fabricated default. Upstream names appearing below inside examples or historical notes are inactive references, not instructions.
