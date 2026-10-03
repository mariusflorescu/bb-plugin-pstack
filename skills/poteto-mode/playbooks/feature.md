### Feature

**You own the design. Plan, review, verify.** Delegate implementation. Stay in the lead.

Size the task first, per the size lanes in poteto-mode's Playbooks section. The lane decides which steps below run, and a step it drops stays as `skip: size <size>`.

1. `how` over the affected subsystem. Settle which layer, service or repo owns the data and behavior before `architect`, and record it as a todo `owner: <answer>`.
2. `architect` for parallel design exploration, behind the design gate. Run it when the implementation admits materially different shapes and the shape is not already decided. Skip it when the user or the PO already agreed on the flow or shape (ticket text, a mockup, an explicit message in the thread), and record `skip: shape decided by <source>`. When it is unclear whether the shape is decided, ask the user one short question before spawning runners. An agreed shape is a preference call no experiment can settle, so this question passes the "classify it before you ask" rule in poteto-mode's Non-negotiables and does not conflict with the **never-block-on-the-human** principle skill.
3. Write the throughput checkpoint as four todo items. A dimension that genuinely does not apply (single file, no fan-out) keeps its item with `n/a: <reason>` rather than being dropped:
   - **Blocking first steps.** Gates run before fan-out.
   - **Independent workstreams.** Disjoint files, services, or layers parallelize. Shared writes serialize.
   - **Shared mutable state.** Default to splitting the target (the **separate-before-serializing-shared-state** principle skill). Serialize only for real invariants.
   - **Smallest safe decomposition.** If one worker is best, name why.
4. Delegate code-writing to a subagent on your feature model, per the pstack delegation rules, with a specific scope (file paths, named data shape and its organizing structure per **principle-model-the-domain**, a state machine over scattered booleans, a table/registry over branching, a typed model over repeated shape assumptions, chosen before the delegate writes logic, and success criteria). When the implementation admits multiple valid shapes (error handling, abstraction layer, test structure), delegate via the **pstack-arena** skill instead so the runners surface the alternatives and the cross-judge guards the pick. The step 2 design gate applies here too, and a decided shape records `skip: shape decided by <source>`. A subagent forbidden to spawn satisfies this step by owning the diff directly with the same review separation. No "standing by" reply that waits on a nested agent. Comments per **Comments**. Surgical edits, re-ground against the source for upstream-derived files. Port shared-primitive improvements to all consumers and verify each. Commit liberally.
5. Verify on the matching surface. "Inconclusive" or wrong-surface is not a pass. Flag it.
6. Rebase into small, ordered commits. Stack follow-ups.
   Use the **sequence-verifiable-units** principle skill, building, verifying, and committing each small unit before the next.
7. If the design is contested, `interrogate` before shipping. This applies in the large or very-large lane, or when the step 2 design gate found the shape open.
8. Run **Opening a PR**.

Code-coupled work (one feature, one migration) goes to a single owner with the checkpoint inline. That owner fans out internally after the blocking phase only when it is a large-slice sub-coordinator whose brief names the worker roles it may spawn. Otherwise the owner is a leaf. It investigates directly and returns open questions to its parent. Parent-level fan-out is for slices that produce independent artifacts (audits, cross-subsystem investigations, competing experiments). Rewrite the checkpoint at phase boundaries. Spawn a fresh owner rather than chaining interrupts.

**Reply:** what you built, what you chose and why, the throughput checkpoint, open decisions. Tables for design alternatives.
