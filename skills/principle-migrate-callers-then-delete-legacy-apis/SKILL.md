---
name: principle-migrate-callers-then-delete-legacy-apis
description: "Apply when introducing a new internal API while old callers still exist. Migrate callers and delete the old API in the same wave instead of preserving compatibility layers."
disable-model-invocation: true
---

# Migrate Callers Then Delete Legacy APIs

When we decide a new API is the right design, migrate callers and remove the old API in the same refactor wave instead of preserving compatibility layers.

**Rule:**
- Do not keep legacy API paths only because internal callers still exist
- Inventory callers, migrate them, and delete the old API immediately
- Treat temporary adapters as exceptional and time-boxed, not default architecture
- Update tests to assert the new contract, and delete tests that only protect pre-refactor implementation details

**When this applies:**
- No external users depend on backward compatibility
- The project can absorb coordinated breaking changes
- The new API is part of a simplification or refactor initiative

Keeping both old and new APIs creates dual-path complexity, slows cleanup, and makes the codebase feel append-only.

## Provenance and local adaptations

Adapted for this personal skill library from the pstack plugin, `cursor/plugins` at commit `889ec4b68fa5aab0e867dad71ec3fdf386ae48f3`, path `pstack/skills/principle-migrate-callers-then-delete-legacy-apis/SKILL.md`. MIT, Copyright (c) 2026 Lauren Tan.

This copy is harness and provider agnostic. Model names, delegation APIs, transcript paths, question tools, config files, and hosting/secret mechanisms that were specific to the upstream author's environment are replaced with instructions to discover what the running harness actually offers. Where a needed capability is absent, the instruction says to surface that rather than silently substituting a paid or fabricated default. Upstream names appearing below inside examples or historical notes are inactive references, not instructions.
