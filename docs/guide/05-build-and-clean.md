# Build the change and clean the diff

The build playbooks share one discipline. Say what you observed, let the playbook demand the evidence. This page shows what to put in the prompt for each common build task, then the cleanup habit that keeps diffs reviewable.

## Prompt each build playbook with what you know

A bug prompt states the symptom and asks for a reproduction first:

```text
/poteto-mode this command emits two records after a retry. repro first, then fix and verify.
```

A feature prompt states the behavior and what must not change:

```text
/poteto-mode add a --json flag. text output stays byte-identical. verify both forms.
```

A refactoring prompt pins behavior before structure moves:

```text
/poteto-mode move parsing into one module, zero behavior change. record the current output first and prove it's unchanged after.
```

A perf prompt states the measurement, not a vibe:

```text
/poteto-mode startup takes 1.8s on this fixture. trace it, fix the measured cause, show me before and after.
```

Each of these routes to its playbook ([Bug fix](../../skills/poteto-mode/playbooks/bug-fix.md), [Feature](../../skills/poteto-mode/playbooks/feature.md), [Refactoring](../../skills/poteto-mode/playbooks/refactoring.md), [Perf issue](../../skills/poteto-mode/playbooks/perf-issue.md)), and the playbook supplies the steps you didn't type: reproduce before fixing, name the data shape before implementing, pin behavior before restructuring, profile before optimizing.

For sustained improvement of one number, there's the [Hillclimb playbook](../../skills/poteto-mode/playbooks/hillclimb.md). Give it the metric, a target, and a floor on attempts, and it loops one hypothesis at a time with a frozen measurement harness. It keeps wins and reverts everything else.

## Write the failing test first with `/pstack-tdd`

When a bug has a cheap local test path, the whole prompt can be two words:

```text
/pstack-tdd implement
```

In context, that's enough. [`/pstack-tdd`](../../skills/pstack-tdd/SKILL.md) writes the smallest test that fails for the intended reason, then the fix, then reruns the test. If a test would need broad harness setup or brittle mocks, the skill says so and uses the closest executable check instead. Don't force a test where a real command is stronger evidence.

## Let the agent pick up the TypeScript rules

[`typescript-best-practices`](../../skills/typescript-best-practices/SKILL.md) has no step in your workflow. Its description tells the agent to use it when reading or editing a `.ts` or `.tsx` file, and the agent loads it on its own when it judges the description fits. No file path triggers it, so when the rules must apply, put `/typescript-best-practices` in your prompt. It turns the type-system principles into concrete rules: discriminated unions, `unknown` at boundaries, exhaustive variants, schema-derived types.

## Clean when the code is ready for review

The [Opening a PR playbook](../../skills/poteto-mode/playbooks/opening-a-pr.md) de-slops the full base-to-branch diff once, when the code is ready for review, and applies [`/unslop`](../../skills/unslop/SKILL.md) to the PR description and commit bodies. pstack doesn't ship a code de-slop skill. The playbook uses a de-slop or simplify skill when your session lists one, and otherwise hands the diff to your refactoring model for a review pass. Outside the playbook, ask for the same outcome in plain words: remove narrating comments, unsupported guards, dead compatibility paths, and unrelated edits.

For prose, `/unslop` takes a target and any extra rules you have:

```text
/unslop the readme changes, no emdashes
```

You'll develop your own shorthand. The skill reads intent fine from terse prompts like `unslop that, tighten it`.

## Strip the comments with `/no-comments`

Comments need their own pass, and not from the agent that wrote them. An author defends its comments the way you'd defend yours. So once per PR, when the code is ready for review, hand them to fresh eyes:

```text
/no-comments the diff
```

[`/no-comments`](../../skills/no-comments/SKILL.md) spawns [Comment Sicko](../../skills/no-comments/references/comment-sicko.md) as a child thread in your environment, so it deletes comments in your working tree. Its keep list is short: license headers, doc comments on a public API, links that explain what code can't, behavior forced by an external dependency you can't reshape, and a comment that states an invariant, a constraint, or a non-obvious why, whoever wrote the code. Everything else goes. A comment that only narrates a surprise in your own code gets no such pass. It comes back as a refactor flag. `/no-comments` then audits Comment Sicko's diff and report, rejects application-code edits and scope escapes, restores a deletion only when a keep-list exception proves it, and fixes the flags it accepts at the root cause. When a comment claims a constraint, "do not remove", the skill offers to encode the claim as a type, test, or lint. Either way, a bare claim comes out.

The division of labor is worth keeping straight. The de-slop pass cleans slop out of the code, `/unslop` cleans it out of prose, and `/no-comments` hands the comments to an agent that didn't write them.

**Pitfall:** cleanup is not optional polish. A diff with narrating comments and defensive dead weight reads as unfinished to reviewers, and the extra code is where the next bug hides. If the diff feels padded, say `deslop it` before you commit, not after review calls it out.

Next: [Verify and ship](./06-verify-and-ship.md).
