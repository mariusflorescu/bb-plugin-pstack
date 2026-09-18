# pstack personal install: manifest and local adaptations

## Source

- Upstream: `cursor/plugins`, repository path `pstack/`
- Pinned commit: `889ec4b68fa5aab0e867dad71ec3fdf386ae48f3`
- Upstream version: pstack `0.15.2` (from `.cursor-plugin/plugin.json`)
- License: MIT, Copyright (c) 2026 Lauren Tan (see `LICENSE`, retained verbatim)

Files were fetched from the pinned commit and verified byte-for-byte against the
vendored copy at the local product repository commit
`a9b064a1ab00a2d40f38b012b812930f05597e2e` (identical). Fetch path used the
pinned download/installer staging; no remote `main` was substituted.

## Install location

This tree is the source of the `bb-plugin-pstack` plugin, installed by path at
`~/Projects/Personal/bb-plugin-pstack` (registered with
`bb plugin install .`). The upstream root shape (`skills/`, `agents/`,
`assets/`, `docs/`, `automations/`, `README.md`, `LICENSE`) is preserved
deliberately: upstream cross-references such as `../../skills/<name>/`,
`../agents/`, `../playbooks/`, and `../references/` resolve against that shape.
Flattening the tree would have silently broken them. The upstream README now
lives at `UPSTREAM-README.md`, because `README.md` is the bb plugin's own readme
for the public repository.

The upstream Cursor plugin manifest (`.cursor-plugin/plugin.json`) was not
carried over, because it is the Cursor plugin-registration file and has no
meaning here.

### How BB sees it

The plugin manifest's `bb.skills` points at `skills/`, so BB imports all 47
`skills/<name>/SKILL.md` files as plugin-tier skills — a slash command plus an
entry in the agent skill list on every provider, not just `acp-cursor`. Each
skill's whole directory (playbooks, references, scripts) ships with it, so the
relative links above keep working from inside a thread.

`server.ts` defines one boolean setting per skill plus a master `skills` switch,
and `bb.agents.configure()` returns only the enabled names for each thread
resolution. That means the switches gate what agents see; `bb skill list` keeps
listing the plugin's declared skills regardless, exactly as the built-in BB
guide plugin behaves.

The earlier standalone copy at `~/.bb/skills/pstack/` is superseded by this
plugin. BB's user-skill scan is one directory deep
(`~/.bb/skills/<name>/SKILL.md`), so that nested copy was never discoverable as
skills in the first place; it should be deleted once this tree is confirmed
good, to avoid a second divergent copy.

`~/.claude/skills` is a plain directory on this host, not a symlink, so the
Cursor-side install is independent of this one.

## Count

- 50 `SKILL.md` files total = 47 under `skills/` (including 23 `principle-*`;
  three of these 47 are renamed `pstack-arena`, `pstack-tdd`,
  `pstack-blast-radius`) + 3 under `automations/benny/skills/`. The aliases
  replace original names and add zero skills.
- The 3 under `automations/benny/skills/` (`setup-benny`, `triage-issue-reports`,
  `reproduce-and-fix-issues`, plus its bundled references). These are retained
  as **inactive reference data**: they are unscheduled, not enabled, and not run.
  They are still *discoverable* in `bb skill list` (they are valid SKILL.md
  files); "inactive" means no trigger, schedule, or run, not "hidden". Each
  carries an in-body banner and a description that requires a configured
  external service and explicit authorization. See `automations/benny/README.md`.

## Collisions and aliases

Three incoming names collided with pre-existing personal skills that are a
different tool by the same name. The pre-existing skills were preserved
byte-identically; the incoming pstack skills were installed under a `pstack-`
alias (directory and frontmatter `name:`), and all internal references were
rewritten to the alias.

| Upstream name | Installed as | Preserved existing skill |
|---|---|---|
| `arena` | `pstack-arena` | `~/.agents/skills/orchestration/arena/SKILL.md` |
| `tdd` | `pstack-tdd` | `~/.agents/skills/tdd/SKILL.md` |
| `blast-radius` | `pstack-blast-radius` | `~/.agents/skills/code/blast-radius/SKILL.md` |

All other upstream names had no collision and were installed unchanged:
`architect`, `automate-me`, `bro`, `create-verification-skill`, `figure-it-out`,
`how`, `interrogate`, `maintain-verification-skill`, `make-bot-ui`, `no-comments`,
`poteto-mode`, the 22 `principle-*` skills, `recall`, `reflect`, `setup-pstack`,
`show-me-your-work`, `swarm`, `teach`, `technical-writing`,
`typescript-best-practices`, `unslop`, `why`.

No other personal skill was overwritten or removed. The five skills from the
earlier scoped install (`bro`, `automate-me`, `make-bot-ui`, `setup-pstack`,
`reflect`) were folded into this tree as their canonical copies.

## What was adapted

Every `SKILL.md` carries its own provenance note naming the upstream commit and
path plus the MIT notice. Adaptations applied across active instruction files
(entrypoints, playbooks, principles, reviewer prompts, docs):

- **Delegation**: no fixed `Task` tool, `subagent_type`, `readonly`, `agent mode`,
  or `run_in_background`. Instructions use the harness's native delegation when it
  has one, with an explicit sequential fallback and an honest note when
  independence is lost.
- **Models**: no hardcoded model slugs or families. Instructions discover the
  session's available models and reasoning efforts, prefer an inherit-the-parent
  choice where valid, never require a fake model for panel diversity, and never
  silently fall back to a paid model.
- **Model discovery, corrected against BB 0.43.** An earlier pass pointed
  `setup-pstack` at a `projects_model_map` tool and `bb projects roles` /
  `bb projects model-map` commands. None of those exist: `bb projects` is not a
  command, project records carry no model fields, and the strings appear nowhere
  in the BB 0.43 bundle. What is real: `bb provider list` enumerates every
  installed provider, `bb provider models <id> --json` returns each model's
  `supportedReasoningEfforts` and `defaultReasoningEffort`, and per-role choice is
  applied at spawn time with
  `bb thread spawn --provider --model --reasoning-level`. BB persists only one
  remembered provider/model pair per project. `setup-pstack` now says so and
  records nothing on the user's behalf; `CAPABILITIES.md` carries the same
  correction. The skill also no longer implies that omitting `--model` inherits
  the parent: on BB it falls back to the project default. BB does inherit the
  origin provider/model/reasoning in a workflow worker's agent call, and the
  skill names that as the one place it holds.
- **Capability claims corrected for a BB host.** The generic "discover the
  harness's mechanism" phrasing stays, because the library is deliberately
  harness-agnostic and BB already injects the `bb-cli` skill and the `workflows`
  orchestration references. What changed is the class of statement a general CLI
  manual cannot refute: a skill asserting a capability is absent. Four such
  claims were false here and are fixed. `CAPABILITIES.md` said there was no
  bundled scheduler (BB ships `bb automation`), understated worktree isolation
  (`--new-environment worktree`), remote execution (`--machine`), and evidence
  lookups (`bb memory`). `opening-a-pr.md` claimed subagents inherit the parent
  worktree, which is false on BB where every spawned thread gets its own
  environment. The five skills that offered "run sequentially in this session"
  as the fallback now require confirming the harness's real concurrency
  capability first, so the degraded path is not the default reading.
  `poteto-mode/SKILL.md` no longer implies an inherited parent model on spawn and
  points at the project's `.bb/AGENTS.md` for the confirmed role mapping.
- **Transcripts**: no Cursor transcript glob. Instructions prefer a native read of
  the active conversation, otherwise the harness's documented active-workspace
  transcript location, and never scan unrelated project directories.
- **Questions/skills/config**: `AskQuestion` becomes "the harness's structured
  question tool when it has one"; `create-skill` becomes a discovered
  skill-authoring skill; the Cursor rules file becomes "record choices where this
  harness keeps configuration", with explicit non-portability language.
- **make-bot-ui** is a provider-neutral, authenticated-webhook workflow: it
  discovers the real webhook API, auth, wake format, and hosting capability;
  asks only for missing inputs; keeps secrets in the host's secure mechanism
  (`bws` on this host); never binds `0.0.0.0` by default; and performs no setup.
- **setup-pstack** discovers providers/models via the harness catalog (for
  example `bb provider models` on a BB host) and states plainly that the choices
  apply to this host only.
- **External actions**: no unconditional commit, push, PR, backlog post, package
  install, deploy, or system mutation. Those require the user's explicit request
  at invocation time; loading a skill is not permission.
- **reflect**: proposes before editing shared skills, with no automatic backlog
  posting.

Upstream names still appear in provenance notes, the upstream README kept at
`UPSTREAM-README.md`, and the inactive `automations/` templates. Those are
labelled inactive, not instructions.

The capabilities pstack leans on that are not universal (delegation, remote
workers, schedulers, MCP servers, control skills, model map, secret manager,
toolchains) are listed with their real status in [`CAPABILITIES.md`](./CAPABILITIES.md).

## Verification

- Frontmatter `name` matches directory for all 50 `SKILL.md` files.
- No duplicate skill names across the installed tree; `bb skill list` reports
  zero duplicate scope+name entries and all expected aliases.
- All 234 relative markdown links checked; the only unresolved one is a literal
  `](url)` placeholder inside an example.
- No hardcoded model slugs, `subagent_type`, `Task`, `run_in_background`,
  `AskQuestion`, `.cursor` path, or `.mdc` reference remain in active skill
  bodies. Remaining Cursor references are confined to the inactive
  `automations/` tree, `UPSTREAM-README.md`, and an explicit "do not carry over
  these slugs" example.
- `show-me-your-work/scripts/log.sh` was inspected before retaining its
  invocation: it is a plain append-only TSV helper with formula-injection
  escaping. The `poteto-mode/scripts/` TypeScript tooling was retained as
  reference; it requires its own Node/Bun runtime and is not auto-run.

## External runtime prerequisites (not provided here)

- `poteto-mode/scripts/` (orch, watch-pr, bootstrap) needs a Node/Bun toolchain
  and, for `watch-pr`, a GitHub token via the external `gh` CLI.
- The `automations/benny` tree needs a specific external automation service.
- Skills that mention MCP evidence lookups need those MCP servers connected.
- `make-bot-ui` needs a real webhook provider and, for external reachability, a
  tunnel or private network.

None of these are installed, started, or promised by this install.
