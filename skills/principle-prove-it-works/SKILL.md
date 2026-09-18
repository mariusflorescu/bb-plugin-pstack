---
name: principle-prove-it-works
description: "Apply after completing a task, before declaring done. Verify against the real artifact (run the feature, read the actual value, inspect the diff), not a proxy, self-report, or 'it compiles.'"
disable-model-invocation: true
---

# Prove It Works

Verify every task output by checking the real thing directly. Do not infer from proxies, self-reports, or "it compiles."

**Why:** Unverified work has unknown correctness. Indirect verification (file mtimes, output freshness, agent self-reports, cached screenshots) feels cheaper than direct observation. Acting on a wrong inference costs far more than checking the source.

**Pattern:** After completing any task, ask: "how do I prove this actually works?"

Check the real thing, not a proxy:
- Check process liveness directly, not indirectly through derived state
- Read the actual value, not a cached or derived representation
- When verification fails, suspect the observation method before suspecting the system

Code and features:
1. Build it (necessary but not sufficient)
2. Run it and exercise the actual feature path
3. Check the full chain: does data flow from input to output?
4. For integrations, test the full communication path end-to-end

Delegation: trust artifacts, not self-reports.
When verifying delegated work, inspect the actual output artifact (git diff, file contents, runtime behavior), not the delegate's summary.

## Script the check when you can

The strongest proof is a deterministic script that re-runs the same comparison, not a one-time eyeball. Write the script, run it, and keep its output as an artifact a reviewer can re-run instead of trusting your word.

Keep the artifact visible for the human. Commit it only for large or complex work where the trail has to be auditable later, like a big port or migration (the **show-me-your-work** skill).

## Provenance and local adaptations

Adapted for this personal skill library from the pstack plugin, `cursor/plugins` at commit `889ec4b68fa5aab0e867dad71ec3fdf386ae48f3`, path `pstack/skills/principle-prove-it-works/SKILL.md`. MIT, Copyright (c) 2026 Lauren Tan.

This copy is harness and provider agnostic. Model names, delegation APIs, transcript paths, question tools, config files, and hosting/secret mechanisms that were specific to the upstream author's environment are replaced with instructions to discover what the running harness actually offers. Where a needed capability is absent, the instruction says to surface that rather than silently substituting a paid or fabricated default. Upstream names appearing below inside examples or historical notes are inactive references, not instructions.
