---
name: no-comments
description: "Spawn Comment Sicko, fix accepted findings, and offer encodings for claimed constraints."
disable-model-invocation: true
---

# No comments

Spawn Comment Sicko. Act on accepted findings.

Defer to Comment Sicko's fresh perspective.

## Scope

The gate runs once, on the full base-to-branch diff, when the code is ready for review. The base branch defaults to `main`, and the working tree counts. That holds whether the PR opens at the end or is already open. It never runs per delegated diff or per commit. A caller may explicitly ask for a partial cleanup of named files or a slice of the diff. That run is allowed, but it does not count as the gate.

A comment that states an invariant, a constraint, or a non-obvious why stays, whoever wrote the code.

## Steps

1. Spawn Comment Sicko as a child thread with your refactoring model, per the pstack delegation rules, in this thread's environment (`--environment "$BB_ENVIRONMENT_ID"`) so its edits land in your tree. Its brief is [`references/comment-sicko.md`](references/comment-sicko.md) pasted verbatim, then the scope and "Do not spawn". Do not restate its rules. Collect its report with `bb thread wait <id>` and `bb thread output <id>`.
2. Inspect its report and diff. Reject application-code edits, scope escapes, exception-protected deletions, misstated `MUST KILL` reasons, and flags that treat kept intentional code as guilty. Reshape flags on our-code surprises stay actionable. Do not restore a comment that only narrates one. Restore a deleted comment that states an invariant, a constraint, or a non-obvious why, whoever wrote the code. A keep survives only with proof it is about something we cannot change, or that it states a true invariant, constraint, or non-obvious why. Audit missed scoped lint and TypeScript suppressions. Correctness or safety suppressions stay actionable `MUST KILL`s. Restore deletions only with exact exceptions and scoped proof. Before accepting thin `IMPORTANT` or `do not remove` kills or keeps, run `/how` or `/why` on their symbol. If a kill is ambiguous, do not restore. If a keep is refuted or still ambiguous, delete it. Revert and rerun one rejected report with the failure named. Reject a second, report it open, and fail `/no-comments`.
3. Fix trivial accepted flags directly by deleting a dead path, dropping a parameter, or using the real API. If any fix needs a shape, run `/architect` once for the accepted set and surrounding code. Stop at the sketch. Architect shapes. Step 4 implements.
4. Implement the smallest root-cause fix in scope. Remove every named workaround. If the root cause is out of scope, land the smallest in-scope fix and report the rest open. The **principle-fix-root-causes** and **principle-redesign-from-first-principles** skills guide intent only. Neither authorizes widening the fence nor fixing instances outside it. Never bolt on symptom guards.
5. Constraint comments say `do not remove`, `do not change wording`, or `talk to X before changing`. Leave keeps about things we cannot change. Offer the cheapest in-scope type, runtime, test, or CI lint. Wait for interactive approval. Unattended and eval require caller pre-approval. If approved, encode then delete. Otherwise keep a comment that states the constraint itself, delete a bare claim, report the constraint open, and sketch out-of-scope work.
6. Report the deletion count, restored comments, reruns, architect sketch, fixes, encoding offers, encodings, unenforced constraints, and other open work.
