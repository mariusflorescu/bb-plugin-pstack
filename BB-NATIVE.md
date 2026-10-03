# BB-native contract

pstack upstream (`cursor/plugins`, path `pstack/`) is written for Cursor. This
plugin ships the same skills adapted to BB. This file is the translation
contract: the per-skill adaptations follow it, and the daily upstream sync
applies it to every incoming change. When upstream text and this contract
disagree, this contract wins.

Keep upstream wording wherever it is harness-neutral. Change only what names a
Cursor mechanism, and replace it with the BB mechanism below, not with vague
"whatever the harness offers" prose. Vague prose is what made agents fall back
to their provider's built-in subagent tool and ignore the model mapping.

## What BB materializes

BB copies each `skills/<name>/` directory into a thread. Nothing else in this
repo reaches a thread: not `agents/`, not `docs/`, not this file. A skill may
link only inside its own directory or to another skill's directory
(`../<other-skill>/...`). Anything a skill needs at runtime lives under its own
`references/`, `playbooks/` or `scripts/`.

The plugin's `server.ts` injects one instruction block into every thread: the
delegation rule and the per-role model mapping (setting `models`, edited by
`/setup-pstack`, laid over the plugin defaults one role at a time). Skills refer
to it as "the pstack delegation rules"; they do not restate the mapping.
Task leads (threads with no parent) delegate meaningful work and independent
verification to BB child threads and coordinate through `bb thread tell`; no
permission needed. Trivial operations (one CLI action, a quick lookup, a
skill's no-op branch) run in the lead.
Children execute their assigned steps and report to the parent. Each brief names
the roles the child may spawn or says "Do not spawn". This scope controls further
delegation even when a playbook says to delegate; other gates still apply.
While a thread's poteto-mode is on, `server.ts` puts poteto-mode's standing
note in front of that block. A message with a `/poteto-mode` or
`$poteto-mode` line turns the mode on, and the chip in the thread header
turns it off or back on. BB applies the block only when it builds the
thread's session, at the first message or a later rebuild such as a BB
restart, so a switch in the middle of a thread takes effect at the next
rebuild.

## Translation table

| Cursor / upstream | BB |
|---|---|
| `Task` tool, "spawn a subagent", `subagent_type`, "delegate" | A child thread: `bb thread spawn --project "$BB_PROJECT_ID" --parent-self --environment "$BB_ENVIRONMENT_ID" --provider <p> --model <m> --reasoning-level <e> --title "<role>: <slice>" --prompt-file <brief>`. A child that writes code in parallel with others takes `--new-environment worktree --base-branch "$(git rev-parse HEAD)"` instead of `--environment`, and the parent commits what that child needs first, because uncommitted changes do not reach a worktree. Provider, model and effort come from the role's entry in the pstack delegation rules. Never the provider's built-in subagent tool (Claude Code `Agent`/`Explore`/`Task`, Codex subagents). |
| `run_in_background: true`, "fire and wait" | Spawning never blocks. Children report their turns to the parent. Collect with `bb thread wait <id>` then `bb thread output <id>`; wait on N children in one background command. |
| Resume / follow up a subagent | `bb thread tell <id> --message-file <path>`. A fresh child with consolidated scope is still preferred over resuming (upstream rule). |
| `readonly: true` subagent | State "read-only: do not edit files, commit or push" in the brief. Spawn into the parent's environment (default) so it reads the same tree. |
| `environment: "cloud"`, cloud VM, cloud agent | `--new-environment worktree --base-branch "$(git rev-parse HEAD)"`. A managed worktree starts from bb's project default branch unless `--base-branch` is given; the parent's commit SHA pins it to the parent's code, so commit first. On another enrolled machine, `--machine <name> --new-environment worktree --base-branch origin/<branch>` after pushing the branch, because a local commit is not on that machine. That child cannot read the parent's absolute paths either, so attach each file it needs with `bb thread spawn --file <absolute path>` (repeatable), which uploads it. |
| `poteto-agent` (`agents/poteto-agent.md`) | Dropped. Only a sub-coordinator child that owns a large or very-large slice gets a brief whose first line is poteto-mode in the child's provider syntax (`/poteto-mode` for Claude Code, `$poteto-mode` for Codex; see the `disable-model-invocation` row), which loads the poteto-mode skill in full, Principles index included, before the child does any work. Implementers, reviewers and helpers get a scoped brief and "Do not spawn". |
| `comment-sicko` (`agents/comment-sicko.md`) | The persona file `no-comments/references/comment-sicko.md`. The caller pastes it verbatim at the top of the child's brief. |
| Model slugs (`grok-*`, `gpt-*`, Cursor model names) and "default X" | The role name only ("your bug-fix model"). The mapping resolves it. |
| `/loop`, wake-ups, polling | A background `bb thread wait` for thread events, or `bb automation create --in <duration>` / `--cron` for time-based wake-ups. |
| `agent-transcripts/`, `~/.cursor/projects/...` | `bb thread log <id> --format minimal --all` and `bb thread output <id>`; the current thread is `--self`. Scratch files go under `$BB_THREAD_STORAGE`. |
| Cursor restart, local agents dead after restart | BB threads persist across app and daemon restarts. After a restart, re-read state with `bb thread list --parent-thread <id> --include-hidden` and `bb thread show`. Every `bb thread list`, project-wide ones included, skips hidden threads without `--include-hidden`. |
| `git show origin/main:pstack/<path>` (re-read a skill file from trunk) | `scripts/read-from-trunk.sh <path>` from poteto-mode's directory (`../poteto-mode/scripts/read-from-trunk.sh` from another skill), with `<path>` as this repo lays it out (`skills/...`). A thread keeps the skill copy BB loaded when it started; the script reads trunk of the source the plugin was installed from. A `git show origin/main:` of the project's own files stays as it is. |
| `/goal` (a durable objective for a long program) | Kept where the root thread's provider supports it (Codex durable Goals, cleared with `bb thread clear-goal <id>`), skipped where it does not. The tick automation (`bb automation create --cron`) keeps the cadence either way. |
| `create-skill` (Cursor built-in) | The `skill-creator` skill (BB guide plugin). |
| `cursor-team-kit` `deslop` | The bundled `deslop` skill (`skills/deslop/`, imported from `cursor-team-kit`; see `MANIFEST.md`) for code; the `unslop` skill for prose. |
| `cursor-team-kit` `control-ui` / `control-cli` | The project's own verification skill if it has one (see `create-verification-skill`), otherwise BB's browser (`bb guide browser`) for web UIs and a BB terminal (`bb guide terminals`) for CLIs/TUIs. |
| Cursor's built-in `babysit` skill | Drop the reference; the Babysit playbook stands on its own. |
| Origin forge (`command -v origin`) | GitHub CLI (`gh`) only. |
| Bugbot | Any review bot on the PR (Bugbot, `claude[bot]`, Copilot). |
| Cursor hooks, `.cursor/` rules, Cursor settings UI | BB: `.bb/AGENTS.md` (project), `~/.bb/AGENTS.md` (user), `.bb/skills/`, or the plugin settings (`bb plugin config pstack ...`). |
| Ask-the-user tool names | "ask the user" (BB routes the provider's native question tool). |
| Cursor's to-do list ("open a todolist", todo items) | The task list that poteto-mode's standing note names. On Claude Code that is `TaskCreate` and `TaskUpdate`, and Claude 5 models get those tools only with `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` in BB's machine environment. BB's Codex threads have no plan tool (probed on 2026-09-28), so Codex keeps `$BB_THREAD_STORAGE/checklist.md` up to date instead. Other providers use their own task list. `server.ts` holds one note per provider in `POTETO_NOTES`. |
| A skill named in bold (`**unslop**`), loaded by Cursor on demand | Read `../<name>/SKILL.md` from the naming skill's base directory. A principle named without its prefix (`the **prove-it-works** principle skill`) is `../principle-<name>/SKILL.md`; keep upstream's short form. Most pstack skills are user-invoked only (`disable-model-invocation`), so a provider's skill tool will not load them. The injected rules say so once, and `scripts/check-bb-native.mjs` fails on a bold skill name that resolves to neither directory. |
| `disable-model-invocation: true` (only the user invokes the skill) | Kept in `SKILL.md`, where Claude Code reads it. Codex ignores it and reads `agents/openai.yaml` beside `SKILL.md` instead, so `scripts/sync-server-skills.mjs` writes `policy.allow_implicit_invocation: false` there for exactly these skills, and the checker fails when the two disagree. Each provider then runs a hidden skill with its own prefix: `/<name>` on Claude Code, `$<name>` on Codex. BB's composer offers both prefixes and hands Codex the text as typed; Codex resolves `$<name>` itself, hidden or not, but matches `/<name>` only against the skills it can see. So a brief that runs a skill in a child uses the child's prefix (the checker's `brief-prefix` rule). Skill text elsewhere keeps upstream's `/<name>` when it tells the user or the agent to run a skill; the rules `server.ts` injects into a Codex thread translate it: "pstack writes /<name>: say and run $<name>". |
| `paths:` (Cursor attaches the skill when the agent works on a matching file) | Kept in `SKILL.md` as upstream wrote it, but it is not what loads the skill: Codex ignores `paths`, and in BB threads Claude Code did not load such a skill by itself when it wrote a new `.ts` file or read one with `grep`. So `server.ts` tells every provider "Before you read or edit a file matching `<glob>`, load the `<name>` skill", from the `SKILL_PATHS` table `scripts/sync-server-skills.mjs` generates. Claude Code will not load a `disable-model-invocation` skill for the model, so a skill with `paths` drops `disable-model-invocation` (typescript-best-practices), and the checker fails on the pair. |

## Local policy for sizing and delegation

These rules are BB-local policy, not translations. They right-size poteto-mode
after an audit of 47 threads found the full ritual on every ticket. When an
upstream change touches one of these lines, keep the rule and bring in the rest
of the change.

1. **Size first.** poteto-mode's Playbooks section opens every task with the
   todo `size: <trivial|small|medium|large|very-large>, <one-line reason>`.
   Trivial runs in the lead. Security, auth, tenant-isolation and data-safety
   work is never trivial, including an already-fixed or no-repro outcome, and
   sits in the small lane at minimum. Small is one implementer and one
   reviewer from another model family, with no how, architect, pstack-arena
   or interrogate. Medium adds how on its simple path. Large and very-large
   run the full playbook. A read-only investigation has its own form of each
   lane. Small is one how explainer child with no implementer and no PR.
   Medium runs how on the path that skill picks, also with no PR. Either way
   the report persists per rule 8. A step a lane drops stays as
   `skip: size <size>`. From the small lane up, a no-repro or no-code-change
   result does not skip a delegated investigation. The Feature, Bug fix,
   Refactoring, Perf issue and Investigation playbooks point at the lanes.
   Architect and interrogate apply only in the large lanes or when rule 2's
   gate finds the shape open. That covers poteto-mode's Non-negotiables, the
   architect step in Bug fix, Perf issue and Refactoring, Feature step 7, and
   the subagent rule in Opening a PR.
2. **Design gate.** Feature step 2 (architect) and step 4 (pstack-arena) run
   only when the implementation admits materially different shapes and the
   shape is not already decided. A shape the user or the PO agreed on records
   `skip: shape decided by <source>`. When that is unclear, the lead asks one
   short question. Whether a shape is agreed is a preference call, so the
   question passes "classify it before you ask". Runner counts and the role
   mapping stay as they are. Architect Phase B carries the same gate and the
   same question.
3. **Child briefs.** Only a sub-coordinator that owns a large or very-large
   slice gets poteto-mode as its brief's first line, and it writes its own
   size line. Implementers, reviewers and helpers get a scoped brief that
   carries the files, the data shape, the size and the success criteria, plus
   "Do not spawn". Only a large-slice sub-coordinator whose brief names worker
   roles fans out. An Autopilot owner is one by its playbook. Every other child
   is a leaf. It investigates directly,
   spawns nothing (Comment Sicko included), and returns open questions to its
   parent. A child never hands its own work to another child of the same
   role.
4. **One delegation rule.** "Task leads delegate meaningful work and
   independent verification to BB child threads and coordinate through
   `bb thread tell`; no permission needed. Trivial operations (one CLI action,
   a quick lookup, a skill's no-op branch) run in the lead." The same text
   appears in `server.ts`, poteto-mode's Subagents section, `README.md`, this
   file and `docs/bb-collaboration-instructions.md`.
5. **Gates once per PR.** One deslop pass and one no-comments pass run once,
   on the full base-to-branch diff, when the code is ready for review. That
   covers a PR opened at the end and one already open, as in the Autopilot
   playbooks. They never run per delegated diff or per commit. A partial
   cleanup a caller asks for explicitly is allowed but does not count as the
   gate. When a leaf child owns the PR, its parent (the lead or the large-slice
   sub-coordinator that spawned it) runs the gate and passes the result back.
   Only a sub-coordinator whose brief names worker roles runs it through its
   own children. A comment that states an invariant, a constraint or a non-obvious
   why stays, whoever wrote the code. poteto-mode's Comments section, the
   no-comments skill and Comment Sicko all hold that rule.
6. **Premise first.** Bug fix checks a `cause confirmed: <runtime evidence>`
   todo before any architect or implementation child. Feature records
   `owner: <answer>` from how before architect. Investigation and swarm state
   the underlying goal in one line before an open-ended fan-out, and ask one
   question when the request does not say why.
7. **Size every follow-up.** Each new user request in a poteto-mode thread
   gets its own size line. A follow-up tweak whose shape the user or the PO
   already decided is small at most. A decided shape on a new request skips
   the design bakeoff through rule 2's gate, not through this cap.
8. **Reports persist.** An architect request that says no code, or whose
   deliverable is a report or roadmap, stops after Phase B's synthesis and
   marks Phase D `skip: report-only`. A report goes to
   `$BB_THREAD_STORAGE/<slug>/` or a docs PR, never only to a managed
   worktree, which BB destroys when the thread is archived.

`server.ts`'s standing notes carry rules 1, 3, 5 and 7 in short form, inside
the 4096-character block.

## Out of scope for adaptation

- Code under `scripts/` that talks to GitHub is kept as upstream wrote it, apart
  from paths into `~/.cursor`.
- `docs/guide/` is upstream's human guide. It is kept for reference and is not
  loaded into threads.

## Sync rule

The daily sync reads the upstream commits after the pinned SHA in `UPSTREAM`
that touch `pstack/` or a skill bundled from `cursor-team-kit`. The bundled
skills are `deslop`, `thermo-nuclear-code-quality-review` and
`what-did-i-get-done`, one `bundle=` line each in `UPSTREAM`. The sync applies
each changed file on top of this repo, runs this table over the changed lines,
and opens a PR. It never merges. See `.bb/skills/sync-upstream/SKILL.md`.
