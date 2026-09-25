### Pause safely

**You own a clean stop. Leave a checkpoint a cold-start agent can resume from.** This is explicit only. On "keep going", "going to bed, keep going", or "don't stop", do not pause.

1. Stop at a safe boundary. Finish the current atomic step or back out of it. Start nothing new, and cancel any nested subagents with `scripts/pause-tree.sh "$BB_THREAD_ID"` from this skill's directory. It pauses every automation that would re-prompt this thread or a descendant, then stops every descendant thread at any depth, hidden ones included, until one pass finds them all settled. A non-zero exit names the threads still running. Do not checkpoint until they have stopped.
2. Take no irreversible action to pause. No PR and no push unless you already had one out.
3. Make the work durable. Commit uncommitted edits as one clear `wip:` commit on the current branch so nothing is lost. If the tree is broken, say so in the commit body in one line.
4. Write the resume note off-context. Capture intent, what you were doing, progress and what's verified, current state, next steps, key files, gotchas, and the automations the script paused (resume each with `bb automation resume <id> --project "$BB_PROJECT_ID"`). For the compaction trigger write it to a file like `$BB_THREAD_STORAGE/<slug>-resume.md`. If a show-me-your-work trail exists, point at it instead of duplicating it.

**Reply:** where you are in the loop, what's on disk versus still in your head (paths, no diff dumps), the commits you made and whether the tree is clean, and the first action on resume. This is a pause, not a final report.
