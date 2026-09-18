# poteto-mode scripts (reference tooling; not auto-run)

These are the upstream pstack scripts, retained as reference. They are **not executed by this skill library and not required by the SKILL.md instructions.** Invoke them only after deciding they fit the running host.

External runtime prerequisites:

- **Node/Bun toolchain.** `bootstrap.ts`, `orch/*.ts`, and `watch-pr/*.ts` are TypeScript targeting the Bun runtime (`bun test`, `Bun.spawnSync`, `bun-types`). They will not run under a bare shell.
- **`commander` dependency** (`package.json`). Install happens only if you deliberately set this up; nothing here installs it.
- **GitHub CLI (`gh`) and a GitHub token** for `watch-pr/` and for the PR column in `worktree-audit.sh`. `watch-pr` also parses Cursor-specific automation ID tokens for bugbot comment detection; on a non-Cursor forge those branches simply never match.
- **Transcript directory.** `worktree-audit.sh` reads a per-workspace transcript directory to fill its `LAST_CHAT` column. Set `PSTACK_TRANSCRIPTS_DIR` to that directory for your harness. The default (`~/.cursor/projects/<slug>/agent-transcripts`) is the upstream author's layout; leave it unset and the column is blank.

None of this runs as part of loading or invoking the skills. Verify behavior yourself before relying on any script.
