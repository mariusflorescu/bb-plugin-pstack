### Multi-phase or multi-PR plan

**You own the plan, not the code. The plan is a checklist an owner runs box by box and the operator audits from the evidence.** The plan is the deliverable. Do not implement.

1. When the change is one or two files with an obvious approach, skip the plan. Say so and stop.
2. Settle open questions by prototype before you write. Run `playbooks/prototype.md` for each. Keep the branch, the SHA, and the screenshots for Appendix A. Ask the operator only about a product or preference call that no run can settle. Give options (the **never-block-on-the-human** principle skill).
3. Explore in subagents per the Subagents section, each brief starting with poteto-mode in the child's provider syntax, `/poteto-mode` or `$poteto-mode` (the **guard-the-context-window** principle skill). Each returns file pointers, conventions, test commands, and entry points. No inlined dumps.
4. Copy the skeleton below into the plan file and fill every placeholder. Unless the operator names a path, write the file under `$BB_THREAD_STORAGE/docs/`. Keep every heading and every sub-block in the order shown. One section per PR. One PR is one change with its own evidence (the **sequence-verifiable-units** principle skill). Name the execution playbook in **How to read this**. Pick between `playbooks/autopilot-full.md` and `playbooks/autopilot-stack.md` per the rule at the end of `playbooks/autopilot-stack.md`. A standing program takes `playbooks/orchestrate.md`.
5. Write under `/technical-writing` in full, then `/unslop`. The body is one Diátaxis mode, how-to. Appendices hold explanation and reference. Each heading states the task or the finding. No long dashes. No mid-sentence colons.
6. Run `node scripts/check-plan.mjs <plan.md>` from this skill's directory and fix every line it prints (the **encode-lessons-in-structure** principle skill).
7. Hand back. Post the plan path and the script's output, then stop. Execution starts on the operator's explicit go, under the execution playbook the plan names.

**Verification.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked (the **prove-it-works** principle skill). That sentence is the verification rule. Every verification block opens with it. The live block is mandatory. Ten lanes at the PR head drive the real surface through its control skill, per the **swarm** skill, on your `swarm workers` model. Each lane is one box with a concrete scenario, the screenshot it saves, and its pass predicate. One lane is the **Regression lane against trunk.** It runs the same load-bearing scenario on trunk and head. If trunk does not have the feature, the lane records that fact and gates the behavior the diff adds plus the end state the user waits for instead of inventing a trunk result. The perf gate is dual-sided. Trunk and head must both produce the named metric. If trunk lacks the feature, also isolate the work the diff adds and set an absolute budget for that work plus the end-to-end state the user waits for. Do not claim a ratio between unlike scenarios. The perf block names the metric, the interleaved probe, the trunk baseline measured first, and the rule with the number that fails. A PR that changes an interaction is review-gated. The operator reviews it in chat with screenshots and a video before merge. A PR that changes no interaction writes `**Review gate.** None. <PR id> is not review-gated.` and no boxes under it.

**Control skill.** Pick it by surface. The project's own verification skill comes first when it has one (see the **create-verification-skill** skill). Without one, browser and web UIs use BB's browser (`bb guide browser`), and CLIs and TUIs use a BB terminal (`bb guide terminals`). Electron and native mobile use whatever driving skill the repo has. A PR that touches two surfaces gets lanes on both. A surface with no control skill is a risk in Appendix C, and its live block still names how each lane drives it.

````markdown
# <Program> plan

<Under ten lines. What changes, for whom, the rule the program enforces, and the PR ids in order.>

## How to read this

One box is one unit of work. Every box names the evidence that checks it. A nested box is a sub-step of the box above it. Check a box only when its evidence exists, a file, a log line, a screenshot, a test run, or a SHA. The body is a how-to. The appendices explain and record.

The program runs the poteto-mode skill's `playbooks/<execution playbook>.md`. <Who merges, and which PR ids are the operator's items that stop at merge-ready.>

Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

## Program checklist

### Arm the program

- [ ] State the protocol and this plan to the operator, then stop. Start execution only on the operator's explicit go.
- [ ] On the operator's go, record the program objective in the decision trail with this exact text. "<The plan path, the PR ids in order, the verification rule, who merges, and the done condition.>" When the root thread's provider offers durable goals (its `composerActions` in `bb provider list --environment "$BB_ENVIRONMENT_ID" --json` include `goal`), also arm a `/goal` with the same text.
- [ ] Read these from trunk at program start. Re-read them at every tick. Read pstack files with the poteto-mode skill's `scripts/read-from-trunk.sh`, not from the copy BB loaded at thread start, and log the trunk revision it prints in the decision trail. If the script fails, log its error in the decision trail, tell the operator once, and use the loaded copy until the script reads again.
  - [ ] `read-from-trunk.sh skills/poteto-mode/playbooks/<execution playbook>.md`
  - [ ] `read-from-trunk.sh skills/swarm/SKILL.md`
  - [ ] `git show origin/main:<control skill path>`, or `bb guide browser` or `bb guide terminals` when the project has no verification skill.
  - [ ] `read-from-trunk.sh skills/poteto-mode/playbooks/opening-a-pr.md`
  - [ ] `read-from-trunk.sh skills/<each other leaf skill the program uses>/SKILL.md`
- [ ] From the root thread, arm the 30-minute audit tick as a BB automation that re-prompts the root on its own provider, model, machine, and permission mode. Never leave the cadence to memory.
  - [ ] Read the root's permission mode from its last turn with `bb thread log "$BB_THREAD_ID" --json --all | jq -r '[.[] | select(.type == "client/turn/requested")][-1].data.execution.permissionMode'`. An automation runs each tick in the permission mode it stores, `auto` or `full` when none is given.
  - [ ] Create the tick paused on the root's environment with `bb automation create --project "$BB_PROJECT_ID" --name "<program> audit tick" --disabled --cron '*/30 * * * *' --timezone <IANA zone> --environment "$BB_ENVIRONMENT_ID" --provider <root provider> --model <root model> --permission-mode <root mode> --prompt "<the tick prompt below>" --json`. Without `--environment`, BB checks the provider on the BB server's machine instead of the root's. Record the `id` it prints in the decision trail.
  - [ ] BB refuses `--environment` together with `--target-thread`, so aim the tick at the root with `bb automation update <id> --project "$BB_PROJECT_ID" --target-thread "$BB_THREAD_ID"`, then start it with `bb automation resume <id> --project "$BB_PROJECT_ID"`.
  - [ ] When the operator changes the root's permission mode, match it with `bb automation update <id> --project "$BB_PROJECT_ID" --permission-mode <mode>`.
  - [ ] Delete the tick at close with `bb automation delete <id> --project "$BB_PROJECT_ID" --yes`.
- [ ] Use this tick prompt, verbatim. "If the operator's latest order is a hold or stand-down, dispatch nothing and end the turn with no reply text. Otherwise re-read the program objective, from the armed /goal or else from the decision trail, and the execution playbook from trunk with the poteto-mode skill's scripts/read-from-trunk.sh. If the script fails, log its error in the decision trail, tell the operator once, and use the loaded copy of the execution playbook until the script reads again. Audit the operation against both and fix drift in this tick. Probe every active lane and judge progress by side effects only. Stand down a stuck lane and dispatch its replacement now. Then post a short status message to the operator in chat only when the audit found a tracked change that no earlier status message reported, such as a PR opened, a code-ready head, a round launched or closed, a verdict, a merge, a stuck agent and the action taken, a blocker added or cleared, or a decision only the operator can make. Name every such change and nothing else. Do not repeat a table, the merged list, or an unchanged blocker. If the audit found none, end the turn with no reply text. Either way, log this tick's row in your decision trail. The row names the items reported, or none."
- [ ] On the operator's hold or stand-down, pause the tick with `bb automation pause <id> --project "$BB_PROJECT_ID"`, log the hold in the decision trail, and send every owner a zero-writes order at once with `bb thread tell`. On the operator's go, resume the tick with `bb automation resume <id> --project "$BB_PROJECT_ID"`.

### Spawn owners

- [ ] Spawn one owner per PR with the full lifecycle the execution playbook names.
- [ ] Follow this dependency graph. Start dependent work only after its parent merges, or base it on the parent branch when the execution playbook stacks.
  - [ ] <PR id> and <PR id> are independent and first. Both branch from `main`.
  - [ ] <PR id> after <PR id>.
- [ ] Hold the file boundaries. <PR id or class> touches only `<glob>`.
- [ ] Hold the review gate. <PR ids> change an interaction. They wait for the operator's review in chat with screenshots and a video before merge.

### PR mechanics, for every PR

- [ ] Use `gh` for every PR operation. Never require `gt`.
- [ ] Open the PR ready, never draft, with `gh pr create --base <base-branch>`. A stack child targets its parent branch.
- [ ] Run the repo's lint and typecheck once before the PR-facing push. Push with hooks on.
- [ ] Run a code de-slop pass before each commit, a de-slop or simplify skill when the session lists one, otherwise a review pass on your refactoring model. Run `/no-comments` before review.
- [ ] Triage every review-bot (Bugbot, Copilot, `claude[bot]`) and security-reviewer comment per the poteto-mode skill's `references/bugbot-triage.md`.
- [ ] Rebase onto current trunk before the code-ready report and babysit. Keep that merge base in fix rounds. Rebase again only at merge prep, on a `git merge-tree` conflict with trunk, or on a CI failure that comes from a change on trunk.

### Verdict and merge, for every PR

- [ ] At the code-ready head SHA and at each later push that changes the patch, run the swarm per the swarm skill. One gates lane. The ten live lanes from the PR's **Verify, live** block. The perf lane from its **Verify, perf** block. Two or more audit lanes, each with its own focus, that read the diff and the receipts and distrust the PR body. The root audits the receipts in the merge-ready report before the verdict.
- [ ] Clean only when every lane is `PASS`. Findings go back to the owner, including a defect that a lane filed as a note. A new head gets a fresh swarm and a fresh verdict, except for results that stay valid under the patch-id rule in `playbooks/shipping.md`.
- [ ] <The merge or append rule from the execution playbook, with the patch-id rule from `playbooks/shipping.md`.>

### Boot recipe, for every live lane

Each live lane is a swarm worker in its own worktree at the PR head (`--new-environment worktree --base-branch origin/<head-branch>`). A worktree separates files, not ports, databases, simulators or browser profiles, so give each lane its own. A resource that cannot be split puts its lanes on other enrolled machines (`--machine <name>`) or runs them one after another. Drive the surface only through the control skill in the reading list above.

- [ ] `git fetch origin <head-branch> && git checkout <head SHA>`.
- [ ] <Start the backend and the surface on this lane's own ports, data directory and browser target. Wait for ready.>
- [ ] <Prove the surface this lane drives is served from this worktree at the head SHA, such as a health endpoint that reports the SHA or the listening process's working directory.>
- [ ] <Deliver input only through the control skill's commands. Name the read-only diagnostics.>
- [ ] Save every screenshot to `$BB_THREAD_STORAGE/swarm-<pr-id>/<slug>.png` and return the absolute paths with the report.

## <Task as a verb phrase> (<PR id>)

**Depends on.** <PR id, or None.>

**Files.**

- [ ] Edit `<path>`.
- [ ] Create `<path>`.
- [ ] Delete `<path>`.

**Build.**

- [ ] <One change. Name the symbol and the file.>

**You see.**

- [ ] <One observable result, with the exact log line or screen state.>

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] <Test file and the case it gains.> Run `<command>`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `swarm workers` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Run <the same load-bearing scenario> at trunk and head. If trunk lacks the feature, record that and gate <the behavior the diff adds plus the end state the user waits for>. Save `<slug>.png`. Pass when <predicate>.
- [ ] Lane 2. <Scenario.> Save `<slug>.png`. Pass when <predicate>.
- [ ] Lane 3. <Scenario.> Save `<slug>.png`. Pass when <predicate>.
- [ ] Lane 4. <Scenario.> Save `<slug>.png`. Pass when <predicate>.
- [ ] Lane 5. <Scenario.> Save `<slug>.png`. Pass when <predicate>.
- [ ] Lane 6. <Scenario.> Save `<slug>.png`. Pass when <predicate>.
- [ ] Lane 7. <Scenario.> Save `<slug>.png`. Pass when <predicate>.
- [ ] Lane 8. <Scenario.> Save `<slug>.png`. Pass when <predicate>.
- [ ] Lane 9. <Scenario.> Save `<slug>.png`. Pass when <predicate>.
- [ ] Lane 10. <Scenario.> Save `<slug>.png`. Pass when <predicate>.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. <What is measured at both trunk and head. If trunk lacks the feature, also name the diff-added work and the end-to-end state the user waits for.>
- [ ] Probe. <The command or procedure, run at trunk and at the head, interleaved. Both sides must produce the metric.>
- [ ] Baseline. Record the trunk <value> first.
- [ ] Rule. <Head against trunk, with the number that fails. If the scenarios differ, add absolute budgets for the diff-added work and the user-visible end state instead of an invalid ratio.>

**Review gate.** The operator reviews before merge.

- [ ] Copy lane <n> screenshots into `<media path>/<pr-id>-review-<slug>.png`.
- [ ] Record a 30 to 60 second video of the change in a lane's worktree. Save it as `<media path>/<pr-id>-review.mp4`.
- [ ] Post the screenshots and the video in chat. Stop at merge-ready. Wait for the operator's click.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Review-bot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] <The owner squash-merges its own PR, or the root appends it to the base-branch stack and the operator lands it bottom-up.>

## Close the program

- [ ] Every box above is checked with its evidence.
- [ ] Reply to the operator with the report the execution playbook names.

## Appendix A. Prototype evidence

<Each open question a prototype answered, with the branch, the SHA, and the artifact links. Each question that stays unproven.>

## Appendix B. Alternatives rejected

<Each approach weighed and why it lost.>

## Appendix C. Risks

<Each risk with the PR it lands in and what the owner watches.>

## Appendix D. Links and reading list

<Docs to read before editing. Which PRs get the how and interrogate skills. The trail per the show-me-your-work skill.>
````

**Reply:** the plan path, the PR ids with their dependencies and the review-gated set, what the prototypes proved and what stays unproven, and the check script's output.
