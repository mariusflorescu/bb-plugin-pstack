---
name: pstack-arena
description: "Spawn N parallel candidates at the same task, pick a base, graft the strongest parts of the losers into it. Use for /pstack-arena, 'arena this', 'throw it in the arena', or when one attempt at a non-trivial artifact would lock in the wrong shape."
disable-model-invocation: true
---

# Arena

Fan out N parallel attempts at the same task. Read every candidate end to end. Pick the strongest as the base. Graft the best ideas from the others into it. Verify the synthesized result.

## Start

Open a todolist with one entry per phase before launching anything.

1. Frame
2. Fan out
3. Cross-judge
4. Pick
5. Graft
6. Verify

## Phase A: Frame

The N candidates will receive the same prompt, so the prompt is the contract.

1. State the artifact each candidate is producing.
2. Derive the rubric. State what success looks like for *this* task, then turn it into 3-6 concrete gradeable criteria. The rubric is the picker's tool in Phase D. Candidates only see the task.
3. Pick the runners. Take one runner per entry of your arena runners line, spawned per the pstack delegation rules. Phase B reseats an entry whose model the provider rejects. Spawn more when the arena covers multiple design directions. Same model N times when the work is generation-bound rather than judgment-sensitive.
4. Assign output paths. Each candidate writes to its own location per the **separate-before-serializing-shared-state** principle skill. In a git repository, a candidate that writes code gets `--new-environment worktree --base-branch <baseline>` and commits on its worktree branch. Resolve the baseline once with `git rev-parse HEAD` in your environment and give every candidate that same SHA, so all of them start from the code you grounded on. A worktree holds only committed files, so commit any uncommitted code the task builds on before you resolve it. Any other candidate (a project that is not a git repository, or an artifact that is not code) spawns into your environment and writes to its own directory `$BB_THREAD_STORAGE/arena-<slug>/candidate-<n>/`, expanded to an absolute path in its brief, because a child's `$BB_THREAD_STORAGE` is its own.

## Phase B: Fan out

Spawn all N candidates before waiting on any, each titled `arena runner <n>: <slug>`. Write each brief to `$BB_THREAD_STORAGE/arena-<slug>/brief-<n>.md` and pass it with `--prompt-file`. Each brief holds the task, the absolute path to the shared grounding, its own output path, and instructions to produce both the artifact and a short rationale.

Each rationale names the alternatives the candidate considered and what it rejected.

Collect every candidate with one background command:

```sh
for id in <candidate ids>; do
  bb thread wait "$id" --timeout 2h && bb thread output "$id"
done
```

A worktree candidate's files live at `.environment.path` in `bb thread show <id> --json`, on the branch `.environment.branchName`. A candidate that fails lands in status `error`, and its wait exits at once saying so. Read the failure with `bb thread log <id> --format minimal`. If the provider rejected the seat's model or effort, at spawn or when the candidate started, pick the closest model of the same family and an effort it lists from `bb provider models <provider> --environment "$BB_ENVIRONMENT_ID" --json`. Spawn that seat again on it with the same brief and environment flags, and say so. If a candidate fails for any other reason, run the provider-retry check in the pstack delegation rules first. Before counting it out, cancel any pending retry and stop the candidate, so it cannot resume and commit on its worktree branch after the synthesis. Then proceed with N-1 and note the dropout in the synthesis record.

## Phase C: Cross-judge

After all Phase B candidates complete, spawn one judge per the pstack delegation rules, titled `arena judge: <slug>`. Prefer a different model family from yours. Take the first entry of your arena cross-judge pool whose family differs. If none does, take the first entry and state in the synthesis note that the judge shares your family. The judge shares your environment, and its brief says it is read-only and must not edit files, commit or push. It sees the rubric and the candidates by path label, scores each criterion, and recommends a base with rationale. It runs in parallel with the parent's reading in Phase D, not with the candidates themselves. Collect it with a background `bb thread wait` then `bb thread output` while you read, and reseat it per Phase B if its provider rejects the model. Don't spawn the judge while candidates are still writing.

## Phase D: Pick a base

Read every candidate end to end before picking.

Score each candidate against the rubric criterion by criterion, not on holistic feel. Compare against the cross-judge. Agreement on the base confirms the pick. Disagreement means one of you is biased or the rubric was ambiguous. Read both rationales before deciding.

Pick the base on which candidate a future maintainer can extend most easily without breaking invariants. Prefer the cleaner boundary or smaller API when two feel tied, per the Laziness Protocol.

Record the pick and the reason in a short synthesis note alongside the base artifact, including the cross-judge's verdict.

## Phase E: Graft

Walk each losing candidate once more and identify what is worth porting into the base. The signal is usually one or two things per candidate, not most of it.

When the base is a worktree candidate, bring its branch into your environment with `git merge` or `git cherry-pick` and graft there. Fold each graft in by hand, per the **redesign-from-first-principles** principle skill. Don't paste mechanically. The result has to remain coherent under one mental model.

Record what was grafted, from which candidate, and what was rejected and why.

When N candidates converge on the same shape, that is a strong agreement signal. Note the convergence in the record and ship the consensus shape. No graft is needed. When N candidates wildly diverge, Phase A was under-specified. Reframe and re-run rather than averaging the divergence.

## Phase F: Verify

The synthesized artifact has to hold up under the same scrutiny as any other output, per the **prove-it-works** principle skill.

If verification surfaces a problem the arena did not catch, either Phase A was wrong (re-frame and re-run) or one candidate caught it and you missed the graft (go back to Phase E). Don't paper over.

## Outputs

One synthesized artifact. One short synthesis note alongside, naming the baseline SHA for worktree candidates, the base, the grafts (with source candidate), the rejections, the dropouts if any, and the verification result.
