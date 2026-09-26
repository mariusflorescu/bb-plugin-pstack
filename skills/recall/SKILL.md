---
name: recall
description: "Reconstruct your recent working context from your own chat history, live state, and the shared record (user reports, prior fixes, incidents), then hand back a tight current-state brief. Use for 'recall my work on X', 'catch me up', 'what have I been working on', 'where did I leave off', before starting or resuming work."
disable-model-invocation: true
---

# Recall

**Before you start or resume work, you rebuild the user's recent working context and hand back a tight capsule of where things stand now and what to do next.**

Keep it tight and on-topic. Read only what the in-scope threads need, then stop.

Your context lives in two records. Your own chat history holds what you did and decided. The shared record holds everything that happened around the same code under other names: the symptoms users keep reporting, the fixes that shipped and got reverted, the errors still firing in prod. That second record is what the **why** skill searches, across source control, the issue tracker, chat and issue channels, long-form docs, and error tracking. A feature with a long bug tail keeps most of its story there, so don't reconstruct it from your transcripts alone.

Your chat history is BB's thread record.

- `scripts/project-threads.sh <days> [topic]` lists this project's threads updated in the last `<days>` days, hidden and archived ones included, newest first, skipping the current thread. With a topic it keeps only threads whose raw log mentions it, with a match count. Don't use `bb thread search`. It searches every project and has no project filter.
- `bb thread log <id> --format verbose --all` reads a whole thread as a timeline. Without `--all` it shows only the newest 20 user turns. The raw events (`--format json --all`) are the only view that keeps every command and its output.
- `bb thread output <id>` gives a thread's final answer.

1. Classify, then route. One specific prior chat to resume is the `session-pickup` playbook, not this. Turning habits into a durable skill is `automate-me`. A human-readable summary of your work is a different task. Recall loads working context across recent chats before you act. If the user already gave you a full state capsule (paths, branch, the change), use it and skip the mining.
2. Lock the scope before searching. Pin the window ("recent" is a real range, default the last 7 days), the topic if named, and the project (default the current one, `$BB_PROJECT_ID`. Never read another project's threads without being asked). State the scope back. Never quietly turn "all" into "recent N".
3. Fan out across your chat history. Run `scripts/project-threads.sh` with the window and topic first. Its rows are the corpus, already scoped to this project and ordered by `updatedAt`. Spawn parallel child threads on your `why investigators` model, per the pstack delegation rules, each taking a slice of those thread IDs. Tell every child to read only the threads in its slice, save each raw log (`bb thread log <id> --format json --all`) under its `$BB_THREAD_STORAGE` and search it for the topic, then read only the relevant regions, and skip obvious noise (eval and test threads, and child threads whose reports already sit in their parent's log). Each returns the same schema, one block per thread: topic, the user's goal, decisions, open threads, struggles and corrections, and artifacts (PRs, tickets, branches), each citing the thread as `@thread:<id>`. For one or two threads, skip the fan-out and search directly. The raw logs stay in the children. This thread gets only their findings.
4. Sweep the shared record whenever the topic names a feature, file, subsystem, area, or bug. This is the default, not a judgment call, and "my work on X" does not exempt it. Hand it to the **why** skill's source investigators, but steer their question from "why was this built this way" to "what's the current state, what's been tried and didn't hold, and what are users still reporting". Reuse its per-source playbooks, run the investigators in parallel with the chat-history mining, and inherit its posture: one investigator per source, null results are findings, skip an unavailable MCP and say so. Fold what comes back into the brief. Skip this step only for pure activity recall with no named target ("what did I do this week"), where your own history and live state are the entire answer.
5. Verify against live state. Take the PRs, branches, and tickets that the mining and the sweep surfaced and check them with `git` and `gh`. `bb thread show <id>` gives a thread's status and the pull request on its branch. When the answer hinges on what an agent actually did (the tools it ran, files it read, errors it hit), read its raw events with `bb thread log <id> --format json --all`, not a timeline format or `bb thread output`.
6. Write the brief to the contract below. Group by thread. Stay on the named topic.

## Output contract

Lead with the capsule, then the thread status, then the problems, then the next move. Deeper detail goes below or gets cut.

- **Capsule.** At most 5 bullets. What this work is and where it stands overall.
- **Threads.** One line each, prefixed with exactly one status tag: `[merged #N]`, `[open PR #N]`, `[in flight <branch>]`, `[verified, uncommitted]`, `[reverted #N]`, or `[planned, not started]`. A thread with no tag is not done yet, so tag it.
- **Problems.** At most 5, the recurring ones. Include the symptoms users keep reporting and any fix that shipped and was reverted, so the next attempt starts where the last one failed.
- **Next move.** The single most useful next action, concrete.

An adjacent feature or ticket stays out unless it blocks this one. When the capsule and thread lines outgrow a screen, cut detail before you cut threads. Write the brief through the **unslop** skill, cite chat findings as `@thread:<id>` and shared-record findings by their source (PR #, ticket ID, chat permalink, error-tracker issue), and sanitize private context before any public output.

**Reply:** the brief, to the contract above.
