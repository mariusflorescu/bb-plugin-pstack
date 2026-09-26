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

## Translation table

| Cursor / upstream | BB |
|---|---|
| `Task` tool, "spawn a subagent", `subagent_type`, "delegate" | A child thread: `bb thread spawn --project "$BB_PROJECT_ID" --parent-self --environment "$BB_ENVIRONMENT_ID" --provider <p> --model <m> --reasoning-level <e> --title "<role>: <slice>" --prompt-file <brief>`. A child that writes code in parallel with others takes `--new-environment worktree --base-branch "$(git rev-parse HEAD)"` instead of `--environment`, and the parent commits what that child needs first, because uncommitted changes do not reach a worktree. Provider, model and effort come from the role's entry in the pstack delegation rules. Never the provider's built-in subagent tool (Claude Code `Agent`/`Explore`/`Task`, Codex subagents). |
| `run_in_background: true`, "fire and wait" | Spawning never blocks. Children report their turns to the parent. Collect with `bb thread wait <id>` then `bb thread output <id>`; wait on N children in one background command. |
| Resume / follow up a subagent | `bb thread tell <id> --message-file <path>`. A fresh child with consolidated scope is still preferred over resuming (upstream rule). |
| `readonly: true` subagent | State "read-only: do not edit files, commit or push" in the brief. Spawn into the parent's environment (default) so it reads the same tree. |
| `environment: "cloud"`, cloud VM, cloud agent | `--new-environment worktree --base-branch "$(git rev-parse HEAD)"`. A managed worktree starts from bb's project default branch unless `--base-branch` is given; the parent's commit SHA pins it to the parent's code, so commit first. On another enrolled machine, `--machine <name> --new-environment worktree --base-branch origin/<branch>` after pushing the branch, because a local commit is not on that machine. That child cannot read the parent's absolute paths either, so attach each file it needs with `bb thread spawn --file <absolute path>` (repeatable), which uploads it. |
| `poteto-agent` (`agents/poteto-agent.md`) | Dropped. A child that works in poteto's style gets a brief whose first line is `/poteto-mode`, which loads the poteto-mode skill in full, Principles index included, before the child does any work. |
| `comment-sicko` (`agents/comment-sicko.md`) | The persona file `no-comments/references/comment-sicko.md`. The caller pastes it verbatim at the top of the child's brief. |
| Model slugs (`grok-*`, `gpt-*`, Cursor model names) and "default X" | The role name only ("your bug-fix model"). The mapping resolves it. |
| `/loop`, wake-ups, polling | A background `bb thread wait` for thread events, or `bb automation create --in <duration>` / `--cron` for time-based wake-ups. |
| `agent-transcripts/`, `~/.cursor/projects/...` | `bb thread log <id> --format minimal --all` and `bb thread output <id>`; the current thread is `--self`. Scratch files go under `$BB_THREAD_STORAGE`. |
| Cursor restart, local agents dead after restart | BB threads persist across app and daemon restarts. After a restart, re-read state with `bb thread list --parent-thread <id> --include-hidden` and `bb thread show`. Every `bb thread list`, project-wide ones included, skips hidden threads without `--include-hidden`. |
| `git show origin/main:pstack/<path>` (re-read a skill file from trunk) | `scripts/read-from-trunk.sh <path>` from poteto-mode's directory (`../poteto-mode/scripts/read-from-trunk.sh` from another skill), with `<path>` as this repo lays it out (`skills/...`). A thread keeps the skill copy BB loaded when it started; the script reads trunk of the source the plugin was installed from. A `git show origin/main:` of the project's own files stays as it is. |
| `/goal` (a durable objective for a long program) | Kept where the root thread's provider supports it (Codex durable Goals, cleared with `bb thread clear-goal <id>`), skipped where it does not. The tick automation (`bb automation create --cron`) keeps the cadence either way. |
| `create-skill` (Cursor built-in) | The `skill-creator` skill (BB guide plugin). |
| `cursor-team-kit` `deslop` | The `unslop` skill for prose; for code, a de-slop or simplify skill if the session lists one, otherwise a review pass by the refactoring role. |
| `cursor-team-kit` `control-ui` / `control-cli` | The project's own verification skill if it has one (see `create-verification-skill`), otherwise BB's browser (`bb guide browser`) for web UIs and a BB terminal (`bb guide terminals`) for CLIs/TUIs. |
| Cursor's built-in `babysit` skill | Drop the reference; the Babysit playbook stands on its own. |
| Origin forge (`command -v origin`) | GitHub CLI (`gh`) only. |
| Bugbot | Any review bot on the PR (Bugbot, `claude[bot]`, Copilot). |
| Cursor hooks, `.cursor/` rules, Cursor settings UI | BB: `.bb/AGENTS.md` (project), `~/.bb/AGENTS.md` (user), `.bb/skills/`, or the plugin settings (`bb plugin config pstack ...`). |
| Ask-the-user tool names | "ask the user" (BB routes the provider's native question tool). |
| A skill named in bold (`**unslop**`), loaded by Cursor on demand | Read `../<name>/SKILL.md` from the naming skill's base directory. A principle named without its prefix (`the **prove-it-works** principle skill`) is `../principle-<name>/SKILL.md`; keep upstream's short form. Most pstack skills are user-invoked only (`disable-model-invocation`), so a provider's skill tool will not load them. The injected rules say so once, and `scripts/check-bb-native.mjs` fails on a bold skill name that resolves to neither directory. |
| `disable-model-invocation: true` (only the user invokes the skill) | Kept in `SKILL.md`, where Claude Code reads it. Codex ignores it, and hiding the skill from Codex (`agents/openai.yaml` with `policy.allow_implicit_invocation: false`) is not an option: BB drops the composer's skill mention and hands Codex `/<name>` as plain text, so Codex runs a skill by slash only when it can see it in its skill list. A hidden plugin skill failed that in BB, for the composer and for a child brief that starts with `/poteto-mode`. So Codex keeps seeing every skill, `server.ts` tells it "load one only when the user, your brief or another pstack skill names it", and the checker fails on any `allow_implicit_invocation: false`. |
| `paths:` (Cursor attaches the skill when the agent works on a matching file) | Kept in `SKILL.md` as upstream wrote it, but it is not what loads the skill: Codex ignores `paths`, and in BB threads Claude Code did not load such a skill by itself when it wrote a new `.ts` file or read one with `grep`. So `server.ts` tells every provider "Before you read or edit a file matching `<glob>`, load the `<name>` skill", from the `SKILL_PATHS` table `scripts/sync-server-skills.mjs` generates. Claude Code will not load a `disable-model-invocation` skill for the model, so a skill with `paths` drops `disable-model-invocation` (typescript-best-practices), and the checker fails on the pair. |

## Out of scope for adaptation

- Code under `scripts/` that talks to GitHub is kept as upstream wrote it, apart
  from paths into `~/.cursor`.
- `docs/guide/` is upstream's human guide. It is kept for reference and is not
  loaded into threads.

## Sync rule

The daily sync reads upstream commits after the pinned SHA in `MANIFEST.md`,
applies each changed file on top of this repo, runs this table over the changed
lines, and opens a PR. It never merges. See `.bb/skills/sync-upstream/SKILL.md`.
