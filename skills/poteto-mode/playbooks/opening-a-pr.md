### Opening a PR

Invoked at the end of every other playbook.

**Worktree.** Work from a git worktree off main. Subagents inherit it. Multiple child threads on the same branch each get their own worktree cut from the branch's pushed tip (`git fetch`, then `bb thread spawn --parent-self --new-environment worktree --base-branch origin/<branch>`) and publish with `git push origin HEAD:<branch>`, or share one environment with `git fetch && git reset --hard origin/<branch>` between them. Dirty branch with unrelated work: patch out, fresh worktree, apply. Snarled worktree: reset from main, redo minimally.

**Commits.** Commit liberally. Rebase into small, ordered commits before opening PRs. Each commit is a future PR: landable, ordered to tell the story. Amend when the fix belongs in a just-made commit. New commit when separable.

**PRs.** De-slop once, on the full base-to-branch diff, when the code is ready for review, with a de-slop or simplify skill if the session lists one, otherwise a review pass by your refactoring model. Then run `/no-comments` once on the same diff. That holds whether the PR opens at the end or is already open. Neither runs per delegated diff or per commit. Write every PR title, PR description, and commit body with `/technical-writing`, then apply `/unslop`. Apply every technical-writing layer except Diátaxis. Use one word for each action, keep articles, and avoid `-ing` when a plain verb works.

**Titles.** Use Conventional Commits in the form `type(scope): subject`. Use `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, or `perf` as the type. Use the changed area, such as `pstack` or `poteto-mode`, as the scope. Keep the subject short and imperative. Name a real symbol when one carries the change. For example, `fix(pstack): retarget opening-a-pr babysit trigger`. Do not add a trailing period.

**Descriptions.** The PR body is a briefing, not the lab notebook. A reviewer who has the diff should learn why the change exists, what is out of scope, and how you proved the change works. The squash commit body is the PR body. If the body would make the squash commit longer than about 40 lines, cut the body.

Use these sections in order. Drop a section when it has nothing to say.

- `## Why`. State the intent and approach in one or two short paragraphs. Do not list SHAs or rebase genealogy. Do not add a "based on main" preamble.
- `## Scope`. Use bullets to list real symbols and paths. Name both sides of a rename or retarget. State what is in and out only when the boundary matters. Do not write a file-by-file essay.
- `## Tradeoffs`. Name only rejected alternatives that a reviewer would otherwise ask about. Skip this section when there was no real choice.
- `## Blast Radius`. In one to three sentences, name who or what the change touches and why the change is safe or risky. State the continuing cost if main stays red without the fix.
- `## Verification`. Name each real run path and its outcome. For a performance change, report one primary number with its unit in `before → after` form. Link the arena or swarm directory for the remaining evidence. Do not include sample-size methodology, swarm recitals, or metric tables.

After these sections, attach videos or screenshots when they prove a claim. Do not paste full SHAs, swarm or arena lane recitals, lever-correction essays, file-by-file checklists, or "CLEAN" verdicts. Put these details in a linked artifact. Do not use `## Summary` or `## Test plan` boilerplate. A commit body does not restate its subject.

**Forge.** Use GitHub CLI (`gh`) for create, edit, view, watch, and merge. Do not require Graphite (`gt`).

**Size and stacks.** Prefer five narrow PRs to one large PR. A stack is a base-branch chain. The root PR targets trunk. Each child branch rebases onto its parent's exact tip and its PR targets the parent branch. Create a child with `gh pr create --base <parent-branch>`. Retarget an existing child with `gh pr edit <pr> --base <parent-branch>`. Branch from trunk only for independent work. Rebase on trunk before substantial stack work.

**Readiness.** Open every PR ready, never as a draft. Omit `--draft` from `gh pr create`. If a PR still opens as a draft, run `gh pr ready <number>`. Run `gh pr view <number>` before you refer to PR status.

**Babysit.** Opening a PR does not start a babysit. Post the URL and keep building. Finish the phase or stack first. Run a separate babysit pass only when the user asks for one after the whole stack exists. A babysit for each new PR stalls the build and spends checks on commits that later waves restart. Push back when feedback drifts from intent.

A PR a subagent opens still gets the de-slop pass and `/no-comments` once, on the full base-to-branch diff, when the code is ready for review, plus `interrogate` in the large or very-large lane or when the design gate in Feature step 2 found the shape open. A large-slice sub-coordinator whose brief names worker roles runs them through its own children. When a leaf child owns the PR, its parent (the lead or the large-slice sub-coordinator that spawned it) runs them on that diff and passes the result back. The subagent posts the URL. Then it returns to the parent without babysitting, unless it is an Autopilot-full or Autopilot-stack owner. That owner's brief assigns the babysit loop and is the ask `playbooks/babysit.md` waits for. The owner starts the loop after its code-ready report and reports merge-ready or STACK-READY as its playbook says. The rules here and in `playbooks/babysit.md` that hold babysitting until a whole stack is built do not apply to that owner.
