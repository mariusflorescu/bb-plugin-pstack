# Unsupported or host-specific capabilities

This library was authored in one environment. The skills are written to *discover*
what the running harness offers and to fall back or stop when a capability is
missing, rather than to assume it. This file lists the capabilities that upstream
pstack leans on and that are not universal, so a reader can see what is expected
and what is not provided here.

None of these are installed, configured, started, or promised by this library. A
skill being loaded is not a grant of any of them.

| Capability | What pstack uses it for | Status here |
|---|---|---|
| Native subagent delegation or child workers | Parallel candidates, reviewers, workers, verifiers | BB: `bb thread spawn` (add `--parent-self` to link the child, `--visibility hidden` to keep a panel out of the sidebar), then `bb thread wait` and `bb thread output` to drain it. Sequential same-lens execution is a last resort with the loss of independence stated, never the default. |
| Isolated worker environments / worktrees | One writer per branch, independent verification | BB: `bb thread spawn --new-environment worktree` gives a worker its own managed worktree, `--new-environment personal` a scratch workspace. Do not hand-roll `git worktree`, and do not assume a spawned thread shares the parent's directory: on BB it does not. |
| Remote/cloud execution | Long autonomous and orchestration runs | BB: threads run on any enrolled machine (`--machine`), or one created from a provider (`bb machine create`). Local execution is a choice, not the only option. |
| Scheduled / self-wake facility | Orchestration audit ticks, autonomous loops | BB ships one: `bb automation create` takes `--cron`, `--at`, or `--in`, runs a prompt or a script, and supports `pause`, `resume`, `run`, `runs`. Use it for audit ticks and loops instead of sleeping inside a thread. |
| Model catalog API/CLI | Per-role model discovery | BB: `bb provider list` / `bb provider models`, both accepting `--environment <id>` because some providers scope their catalog per workspace. |
| Per-role model configuration | Applying a distinct provider/model/effort per role | Discover. BB applies the choice per spawn (`bb thread spawn --provider --model --reasoning-level`) and keeps only one remembered provider/model pair per project; there is no per-role store, so the mapping is presented, not persisted. |
| Reasoning-effort discovery | Knowing which effort levels a model really accepts | BB: `bb provider models <id> --json` exposes `supportedReasoningEfforts` and `defaultReasoningEffort` per model. |
| MCP/tool evidence servers | `why`, `tooling-reviewer` context lookups | Discover. BB also has a first-class store: `bb memory search`, `get`, `add`, `catalog`, plus plugin-contributed tools. Report categories with no matching source. |
| Project control/verification skill (`control-ui`, `control-cli`, `verify-*`) | Driving a real surface for proof | Not bundled. Generate a project-local verification skill or use one the repo has. |
| Prose-cleanup skill (`deslop`) | Stripping AI tells before commit | Not bundled. Use a discovered equivalent if present. |
| External control-skill plugin / automation product (benny) | Webhook automations, issue triage | Not bundled, not scheduled. See `automations/benny/README.md`. |
| Secret manager | Webhook/API credentials | Use the host's mechanism. On this host, the `bws` wrapper. Never plaintext. |
| Node/Bun toolchain, `gh`, GitHub token | `poteto-mode/scripts/` orchestration and PR watching | Not installed. See `skills/poteto-mode/scripts/README.md`. |

Where a capability is absent, the correct behaviour is to say so and take the
documented fallback, not to invent a substitute.
