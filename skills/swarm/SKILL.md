---
name: swarm
description: "Fan out N parallel workers, drain them, and return one report. Use for /swarm, 'swarm this', or parallel coverage, races, gauntlets, and exploration."
disable-model-invocation: true
---

# Swarm

Fan out N parallel workers, each a BB child thread. They may cover separate slices, race the same brief, or mix both. The parent waits, aggregates, and returns one report.

## Start

Open a todolist with one entry per phase before launching anything.

1. Frame
2. Fan out
3. Aggregate
4. Report

## Phase A: Frame

1. State the done predicate and the artifact or report the swarm must return.
2. Choose the shape. Partition into slices, race N workers on identical briefs, or mix both. For a race or mixed shape, declare `first pass`, `rank all`, or `best-of` before spawning.
3. Set N from the user or derive it from the shape. N is total workers, not BB's limit on concurrently running threads.
4. Every worker runs on your swarm workers model, spawned per the pstack delegation rules. If `bb thread spawn` rejects it, pick the closest model of the same family from `bb provider models <provider>`, spawn with it, and say so. For a model race, name each arm's provider, model and effort up front.
5. Give each worker its own writable output when it writes. When workers verify or measure commits, each brief names the exact SHAs. A measurement brief also names the method (sample count, what one sample is, order). The worker records both in its result.

## Phase B: Fan out

Spawn all N workers before waiting on any. Write each brief to `$BB_THREAD_STORAGE/swarm/worker-<n>.md`, pass it with `--prompt-file`, and title the worker `swarm worker: <slice or arm>`. Give each worker `--new-environment worktree` so it has its own checkout. Spawn into your environment instead (omit `--new-environment`) only when the worker needs your uncommitted working tree, and then its brief says it is read-only and must not edit files, commit or push. Add `--machine <name>` to run a worker on another enrolled machine.

When a worker must start from a non-default branch, pass `--base-branch <ref>`, with `origin/<branch>` for a pushed branch.

Every brief stands alone. Include the goal, scope, exact slice or race arm, how to verify, and what to report. The worker's final message is its report. Reports use `PASS`, `ISSUES`, or `BLOCKED` with evidence. A worker that can prove a defect reports `ISSUES` and lists every issue it can prove, not only the first.

Collect every worker with one background command. Set the timeout to the longest a worker should need.

```sh
for id in <worker ids>; do
  bb thread wait "$id" --timeout 2h && bb thread output "$id"
done
```

A worker that fails never reaches idle, so its wait times out. Check it with `bb thread show <id>`. If a worker drops out, proceed with N-1 and note it.

## Phase C: Aggregate

Read each worker's final report. Drop a result that does not record the SHAs and method its brief names, and rerun that worker once. After a second miss, record a gap. A gap does not count as a pass. For coverage, every required slice needs a result. For a race, apply the selection rule declared up front. Use first pass, rank all, or best-of. Do not paste raw worker dumps.

Keep a compact result table, one-line evidenced issues, and explicit gaps or dropouts.

## Phase D: Report

Return one consolidated in-chat report with the table, issue one-liners, gaps or dropouts, and the race rule when used.
