### Bug fix

**The task lead owns planning, review, and verification.** Delegate investigation and the fix to BB child threads. Scoped children execute their assigned steps and report back.

Size the task first, per the size lanes in poteto-mode's Playbooks section. The lane decides which steps below run, and a step it drops stays as `skip: size <size>`.

Be scientific. Every shipped line traces to runtime evidence. Belt-and-suspenders that "might help" is a hypothesis, not a fix. It does not ship. When evidence refutes a hypothesis, revert what it motivated. The smallest change the evidence justifies ships, nothing more.

1. Reproduce it yourself on the matching surface via the control skill (Non-negotiables), even when a debug or instrumentation protocol says to ask the user to reproduce. Ask the user only with a stated, specific reason the control surface cannot reach the target, and only after driving it as far as it goes. If it won't reproduce directly, synthesize the trigger, tighten conditions, or instrument until it fires.
2. Binary-search the cause. Form the candidate hypotheses, then rule them out until one survives. Seed them with `how` over the affected subsystem and the **why** skill for regression history. Each pass, take the split that cuts the most remaining problem space, get runtime evidence, eliminate. When program state is unclear, add instrumentation or logging and read it as the code runs. Don't guess. Drive a long or stubborn hunt with the wake mechanism from the Autonomous run playbook (`playbooks/autonomous-run.md`). Confirm the surviving *mechanism* with runtime evidence before the step-3 architect/interrogate fan-out, and record it as a todo `cause confirmed: <runtime evidence>`.
3. Plan the fix. If it crosses a function boundary in the large or very-large lane, or the design gate in Feature step 2 finds the shape open, `architect` first. Delegate implementation to a subagent on your bug-fix model, per the pstack delegation rules, with a specific scope. No architect or implementation child starts until the `cause confirmed` todo is checked.
4. Verify on the same surface. The original repro now passes. "Inconclusive" or wrong-surface is not a pass. Flag it. Unit tests show branch behavior, not bug absence.
5. Stage the commits so the failing repro lands before the fix in git history. See the **pstack-tdd** skill for the failing-test-first cadence when the bug has a cheap local test path. Skip it when the test would be expensive, integration-heavy, or unclear.
   This is the canonical **sequence-verifiable-units** principle skill, the failing test first and the fix on top.
6. Run **Opening a PR**.

**Reply:** what was broken, root cause, fix, how you verified. Paste failing-then-passing repro output verbatim.
