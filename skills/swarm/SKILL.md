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
4. Every worker runs on your swarm workers model, spawned per the pstack delegation rules. For a model race, name each arm's provider, model and effort up front.
5. Give each worker its own writable output when it writes. When workers verify or measure commits, each brief names the exact SHAs. A measurement brief also names the method (sample count, what one sample is, order). The worker records both in its result.

## Phase B: Fan out

Spawn all N workers before waiting on any. Write each brief to `$BB_THREAD_STORAGE/swarm/worker-<n>.md`, pass it with `--prompt-file`, and title the worker `swarm worker: <slice or arm>`.

Pick each worker's environment before spawning it. A worker that edits, builds or runs the code gets `--new-environment worktree`, its own checkout of committed files. A worker that only reads spawns into your environment (omit `--new-environment`), where it also sees your uncommitted changes, and its brief says it is read-only and must not edit files, commit or push. When the project is not a git repository, every worker spawns into your environment and writes only to its own output from step 5. To run a worker on another enrolled machine, read-only or not, give it `--machine <name> --new-environment worktree` in place of `--environment`. BB rejects `--machine` next to an existing environment ID, because that environment already fixes the machine.

Pin every worktree worker to one commit, resolved once before the fan-out, so workers racing the same brief start from the same code: `--base-branch "$(git rev-parse HEAD)"` after committing your uncommitted changes, or `--base-branch "$(git rev-parse <branch>)"` for another local branch. A worker on another machine needs a pushed ref: push first and pass `--base-branch origin/<branch>`.

Every brief stands alone. Include the goal, scope, exact slice or race arm, how to verify, and what to report. The worker's final message is its report. Reports use `PASS`, `ISSUES`, or `BLOCKED` with evidence. A worker that can prove a defect reports `ISSUES` and lists every issue it can prove, not only the first.

Collect every worker with one background command. Set the timeout to the longest a worker should need.

```sh
for id in <worker ids>; do
  bb thread wait "$id" --timeout 2h && bb thread output "$id"
done
```

A worker that fails lands in status `error`, and its wait exits at once saying so. Read the failure with `bb thread log <id> --format minimal`. If the provider rejected the worker's model or effort, at spawn or when the worker started, pick the closest model of the same family and an effort it lists from `bb provider models <provider> --environment "$BB_ENVIRONMENT_ID" --json`, with `--machine <name>` in place of `--environment` for a worker you sent to another machine. Spawn that worker again on it with the same brief and environment flags, and say so. For any other failure, run the provider-retry check in the pstack delegation rules first. A worker that is not coming back is a dropout: cancel its pending retry and stop it, so it cannot resume writing, then proceed with N-1 and note it.

## Phase C: Aggregate

Read each worker's final report. Drop a result that does not record the SHAs and method its brief names, and respawn that worker once. After a second miss, record a gap. A gap does not count as a pass. For coverage, every required slice needs a result. For a race, apply the selection rule declared up front. Use first pass, rank all, or best-of. Do not paste raw worker dumps.

Keep a compact result table, one-line evidenced issues, and explicit gaps or dropouts.

## Phase D: Report

Return one consolidated in-chat report with the table, issue one-liners, gaps or dropouts, and the race rule when used.
