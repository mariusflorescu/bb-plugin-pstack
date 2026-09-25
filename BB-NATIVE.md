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
`/setup-pstack`). Skills refer to it as "the pstack delegation rules"; they do
not restate the mapping.

## Translation table

| Cursor / upstream | BB |
|---|---|
| `Task` tool, "spawn a subagent", `subagent_type`, "delegate" | A child thread: `bb thread spawn --project "$BB_PROJECT_ID" --parent-self --environment "$BB_ENVIRONMENT_ID" --provider <p> --model <m> --reasoning-level <e> --title "<role>: <slice>" --prompt-file <brief>`. A child that writes code in parallel with others takes `--new-environment worktree` instead of `--environment`. Provider, model and effort come from the role's entry in the pstack delegation rules. Never the provider's built-in subagent tool (Claude Code `Agent`/`Explore`/`Task`, Codex subagents). |
| `run_in_background: true`, "fire and wait" | Spawning never blocks. Children report their turns to the parent. Collect with `bb thread wait <id>` then `bb thread output <id>`; wait on N children in one background command. |
| Resume / follow up a subagent | `bb thread tell <id> --message-file <path>`. A fresh child with consolidated scope is still preferred over resuming (upstream rule). |
| `readonly: true` subagent | State "read-only: do not edit files, commit or push" in the brief. Spawn into the parent's environment (default) so it reads the same tree. |
| `environment: "cloud"`, cloud VM, cloud agent | `--new-environment worktree` (isolated managed worktree, optionally `--base-branch <ref>`), or `--machine <name>` for another enrolled machine. |
| Named agents (`poteto-agent`, `comment-sicko` in `agents/`) | A persona file inside the owning skill (`poteto-mode/references/poteto-agent.md`, `no-comments/references/comment-sicko.md`). The caller pastes it at the top of the child's brief. |
| Model slugs (`grok-*`, `gpt-*`, Cursor model names) and "default X" | The role name only ("your bug-fix model"). The mapping resolves it. |
| `/loop`, wake-ups, polling | A background `bb thread wait` for thread events, or `bb automation create --in <duration>` / `--cron` for time-based wake-ups. |
| `agent-transcripts/`, `~/.cursor/projects/...` | `bb thread log <id> --format minimal --all` and `bb thread output <id>`; the current thread is `--self`. Scratch files go under `$BB_THREAD_STORAGE`. |
| Cursor restart, local agents dead after restart | BB threads persist across app and daemon restarts. After a restart, re-read state with `bb thread list --parent-thread <id>` and `bb thread show`. |
| `create-skill` (Cursor built-in) | The `skill-creator` skill (BB guide plugin). |
| `cursor-team-kit` `deslop` | The `unslop` skill for prose; for code, a de-slop or simplify skill if the session lists one, otherwise a review pass by the refactoring role. |
| `cursor-team-kit` `control-ui` / `control-cli` | The project's own verification skill if it has one (see `create-verification-skill`), otherwise BB's browser (`bb guide browser`) for web UIs and a BB terminal (`bb guide terminals`) for CLIs/TUIs. |
| Cursor's built-in `babysit` skill | Drop the reference; the Babysit playbook stands on its own. |
| Origin forge (`command -v origin`) | GitHub CLI (`gh`) only. |
| Bugbot | Any review bot on the PR (Bugbot, `claude[bot]`, Copilot). |
| Cursor hooks, `.cursor/` rules, Cursor settings UI | BB: `.bb/AGENTS.md` (project), `~/.bb/AGENTS.md` (user), `.bb/skills/`, or the plugin settings (`bb plugin config pstack ...`). |
| Ask-the-user tool names | "ask the user" (BB routes the provider's native question tool). |
| A skill named in bold (`**unslop**`), loaded by Cursor on demand | Read `../<name>/SKILL.md` from the naming skill's base directory. Most pstack skills are user-invoked only (`disable-model-invocation`), so a provider's skill tool will not load them. The injected rules say so once. |

## Out of scope for adaptation

- Code under `scripts/` that talks to GitHub is kept as upstream wrote it, apart
  from paths into `~/.cursor`.
- `docs/guide/` is upstream's human guide. It is kept for reference and is not
  loaded into threads.

## Sync rule

The daily sync reads upstream commits after the pinned SHA in `MANIFEST.md`,
applies each changed file on top of this repo, runs this table over the changed
lines, and opens a PR. It never merges. See `.bb/skills/sync-upstream/SKILL.md`.
