---
name: principle-exhaust-the-design-space
description: "Apply when facing a novel UI interaction or architectural decision with no precedent in the codebase. Build 2-3 competing prototypes and compare side by side before committing."
disable-model-invocation: true
---

# Exhaust the Design Space

When a novel interaction or architectural decision has no established precedent, explore several concrete alternatives before implementation. Building the wrong thing costs more than exploring three options.

**The rule.** When the right answer is not obvious, build 2-3 competing prototypes or sketches. Compare them side by side. Only then commit. Design it twice is this rule by another name. A second flavor of the first shape does not count.

**When it applies:**
- Novel UI interactions (no prior art in the codebase)
- Architectural choices with multiple viable approaches
- Product design decisions where user experience depends on feel, not logic

**When it doesn't:**
- Mechanical implementation where the pattern is established
- Bug fixes or refactors with a clear target state
- Changes where constraints dictate a single viable approach

## Provenance and local adaptations

Adapted for this personal skill library from the pstack plugin, `cursor/plugins` at commit `889ec4b68fa5aab0e867dad71ec3fdf386ae48f3`, path `pstack/skills/principle-exhaust-the-design-space/SKILL.md`. MIT, Copyright (c) 2026 Lauren Tan.

This copy is harness and provider agnostic. Model names, delegation APIs, transcript paths, question tools, config files, and hosting/secret mechanisms that were specific to the upstream author's environment are replaced with instructions to discover what the running harness actually offers. Where a needed capability is absent, the instruction says to surface that rather than silently substituting a paid or fabricated default. Upstream names appearing below inside examples or historical notes are inactive references, not instructions.
