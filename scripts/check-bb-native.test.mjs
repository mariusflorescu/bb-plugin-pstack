// Rerunnable check for scripts/check-bb-native.mjs: node --test scripts/
import { test, after } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, copyFileSync, rmSync, symlinkSync } from "node:fs";
import { join, dirname } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const SCRIPTS = fileURLToPath(new URL(".", import.meta.url));

function check(files) {
  const root = mkdtempSync(join(tmpdir(), "check-bb-native test with spaces-"));
  after(() => rmSync(root, { recursive: true, force: true }));
  for (const [path, text] of Object.entries({ "scripts/check-bb-native.mjs": null, "scripts/frontmatter.mjs": null, ...files })) {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    if (text === null) copyFileSync(join(SCRIPTS, path.slice("scripts/".length)), join(root, path));
    else writeFileSync(join(root, path), text);
  }
  symlinkSync(join(SCRIPTS, "..", "node_modules"), join(root, "node_modules"));
  return spawnSync("node", ["scripts/check-bb-native.mjs"], { cwd: root, encoding: "utf8" });
}

test("a bold skill name must resolve, directly or as a principle without its prefix", () => {
  const run = check({
    "server.ts": 'const SKILL_NAMES = [\n  "a",\n  "principle-prove-it-works",\n] as const;\n',
    "skills/principle-prove-it-works/SKILL.md": "---\nname: principle-prove-it-works\ndescription: x\n---\n",
    "skills/a/SKILL.md": [
      "---",
      "name: a",
      "description: x",
      "---",
      "Apply the **prove-it-works** principle skill, then the **principle-prove-it-works** one.",
      "Use the **skill-creator** skill. Gather **evidence** first.",
      "See the **prove-it-work** principle skill.",
      "Read the **a** and **prove-it-wroks** principle skills.",
      "Race it with **pstack-arnea**.",
      "",
    ].join("\n"),
  });
  assert.equal(run.status, 1, run.stderr);
  assert.equal(
    run.stdout,
    [
      "a/SKILL.md:7 [skill-name] **prove-it-work** has no skills/prove-it-work/ or skills/principle-prove-it-work/",
      "a/SKILL.md:8 [skill-name] **prove-it-wroks** has no skills/prove-it-wroks/ or skills/principle-prove-it-wroks/",
      "a/SKILL.md:9 [skill-name] **pstack-arnea** has no skills/pstack-arnea/ or skills/principle-pstack-arnea/",
      "",
      "1/2 skills clean, 3 findings",
      "",
    ].join("\n")
  );
});

test("BB CLI usage the contract rules out is flagged", () => {
  const run = check({
    "server.ts": 'const SKILL_NAMES = [\n  "a",\n] as const;\n',
    "skills/a/SKILL.md": [
      "---",
      "name: a",
      "description: x",
      "---",
      "If a child never reaches idle, drop it.",
      'Run `bb provider models codex --environment "$BB_ENVIRONMENT_ID" --json`, then `bb provider list --machine mini`.',
      "Run `bb provider models codex --json`.",
      "Walk `bb thread list --parent-thread <id> --include-hidden`, then `bb thread list --project x --include-hidden --json | jq .`.",
      "Walk `bb thread list --parent-thread <id>`.",
      "Mine `bb thread list --project x`, not `bb thread list --parent-thread y --include-hidden`.",
      "Re-read `git show origin/main:pstack/skills/swarm/SKILL.md`, and `git show origin/main:docs/verify.md` for the project.",
      'Pin it with `--base-branch "$(git rev-parse HEAD)"`, or `--base-branch origin/<branch>` elsewhere. Omitting `--base-branch` uses the default.',
      "Stack it with `--new-environment worktree --base-branch <parent branch>`.",
      "Pass `--base-branch <ref>`; a worker on another machine needs a pushed branch, `origin/<branch>`.",
      "Give it `--base-branch <baseline>`, resolved once with `git rev-parse HEAD`.",
      'Fetch the PR head, then spawn with `--base-branch "$(git rev-parse FETCH_HEAD)"`.',
      "",
    ].join("\n"),
  });
  assert.equal(run.status, 1, run.stderr);
  assert.equal(
    run.stdout,
    [
      "a/SKILL.md:5 [wait-error] a failed child is in status error and bb thread wait exits at once; read bb thread log <id>: If a child never reaches idle, drop it.",
      'a/SKILL.md:7 [provider-host] pass --environment "$BB_ENVIRONMENT_ID" or --machine; without one bb reads the server\'s machine: Run `bb provider models codex --json`.',
      "a/SKILL.md:9 [hidden-children] add --include-hidden, or hidden threads are skipped: Walk `bb thread list --parent-thread <id>`.",
      "a/SKILL.md:10 [hidden-children] add --include-hidden, or hidden threads are skipped: Mine `bb thread list --project x`, not `bb thread list --parent-thread y --include-hidden`.",
      "a/SKILL.md:11 [trunk-read] re-read pstack from trunk with poteto-mode's scripts/read-from-trunk.sh skills/<path>: Re-read `git show origin/main:pstack/skills/swarm/SKILL.md`, and `git show origin/main:docs/verify.md` for the project.",
      'a/SKILL.md:13 [base-branch] pin a worktree to "$(git rev-parse HEAD)" after committing, or to a pushed origin/<branch>; a local branch moves: Stack it with `--new-environment worktree --base-branch <parent branch>`.',
      "",
      "0/1 skills clean, 6 findings",
      "",
    ].join("\n")
  );
});

test("a run's built-in PR tool is flagged, a draft field in code is not", () => {
  const run = check({
    "server.ts": 'const SKILL_NAMES = [\n  "a",\n] as const;\n',
    "skills/a/SKILL.md": [
      "---",
      "name: a",
      "description: x",
      "---",
      "Open it with `gh pr create --base main`, never `--draft`.",
      "When the run provides a built-in PR tool, create the PR through it.",
      "Set `draft: false` on every creation call.",
      "",
    ].join("\n"),
    "skills/a/scripts/policy.test.ts": "const policy = { allowDraft: false, isDraft: false };\n",
  });
  assert.equal(run.status, 1, run.stderr);
  assert.equal(
    run.stdout,
    [
      "a/SKILL.md:6 [pr-tool] BB has no PR-creating tool; gh covers every PR operation: When the run provides a built-in PR tool, create the PR through it.",
      "a/SKILL.md:7 [pr-tool] BB has no PR-creating tool; gh covers every PR operation: Set `draft: false` on every creation call.",
      "",
      "0/1 skills clean, 2 findings",
      "",
    ].join("\n")
  );
});

test("a skill's failure paragraph must run the provider-retry check, a script need not", () => {
  const run = check({
    "server.ts": 'const SKILL_NAMES = [\n  "a",\n] as const;\n',
    "skills/a/SKILL.md": [
      "---",
      "name: a",
      "description: x",
      "---",
      "A worker that fails lands in status `error`. For any other failure, run the provider-retry check in the pstack delegation rules first.",
      "A worker that fails lands in status `error`. Proceed with N-1 and note it.",
      "",
    ].join("\n"),
    "skills/a/scripts/wait.sh": "# a child in status error makes bb thread wait exit at once\n",
  });
  assert.equal(run.status, 1, run.stderr);
  assert.equal(
    run.stdout,
    [
      "a/SKILL.md:6 [retry-check] run the provider-retry check in the pstack delegation rules before counting a failed child out: A worker that fails lands in status `error`. Proceed with N-1 and note it.",
      "",
      "0/1 skills clean, 1 findings",
      "",
    ].join("\n")
  );
});

test("in a shell script only a bb thread list call needs --include-hidden, not a comment or message naming it", () => {
  const run = check({
    "server.ts": 'const SKILL_NAMES = [\n  "a",\n] as const;\n',
    "skills/a/SKILL.md": "---\nname: a\ndescription: x\n---\n",
    "skills/a/scripts/walk.sh": [
      "# `bb thread list --parent-thread` skips hidden threads",
      'kids=$(bb thread list --parent-thread "$1" --include-hidden --json) || fail "bb thread list failed"',
      "all=$(bb thread list --json) || fail 'bb thread list --json failed'",
      "",
    ].join("\n"),
  });
  assert.equal(run.status, 1, run.stderr);
  assert.equal(
    run.stdout,
    [
      "a/scripts/walk.sh:3 [hidden-children] add --include-hidden, or hidden threads are skipped: all=$(bb thread list --json) || fail 'bb thread list --json failed'",
      "",
      "0/1 skills clean, 1 findings",
      "",
    ].join("\n")
  );
});

test("Codex's policy file must match disable-model-invocation, paths cannot be user-only, and frontmatter must be YAML", () => {
  const policy = "policy:\n  allow_implicit_invocation: false\n";
  const run = check({
    "server.ts": 'const SKILL_NAMES = [\n  "broken",\n  "hidden",\n  "leaky",\n  "orphan",\n  "plain",\n  "pathy",\n  "stuck",\n] as const;\n',
    "skills/broken/SKILL.md": "---\nname: broken\ndescription: a: b: c\n---\n",
    "skills/hidden/SKILL.md": "---\nname: hidden\ndescription: x\ndisable-model-invocation: true\n---\n",
    "skills/hidden/agents/openai.yaml": policy,
    "skills/leaky/SKILL.md": "---\nname: leaky\ndescription: x\ndisable-model-invocation: true # explicit only\n---\n",
    "skills/orphan/SKILL.md": "---\nname: orphan\ndescription: x\n---\n",
    "skills/orphan/agents/openai.yaml": policy,
    "skills/plain/SKILL.md": "---\nname: plain\ndescription: x\n---\n",
    "skills/plain/agents/openai.yaml": "interface:\n  display_name: Plain\n",
    "skills/pathy/SKILL.md": '---\nname: pathy\ndescription: x\npaths: ["**/*.ts"]\n---\n',
    "skills/stuck/SKILL.md": '---\nname: stuck\ndescription: x\npaths:\n- "**/*.ts"\ndisable-model-invocation: true\n---\n',
    "skills/stuck/agents/openai.yaml": policy,
  });
  assert.equal(run.status, 1, run.stderr);
  const [broken, ...rest] = run.stdout.split("\n");
  assert.match(broken, /^broken \[yaml\] invalid SKILL\.md frontmatter or agents\/openai\.yaml: /);
  assert.deepEqual(rest, [
    "leaky/agents/openai.yaml [codex-policy] must set allow_implicit_invocation: false exactly when SKILL.md sets disable-model-invocation: true; run node scripts/sync-server-skills.mjs",
    "orphan/agents/openai.yaml [codex-policy] must set allow_implicit_invocation: false exactly when SKILL.md sets disable-model-invocation: true; run node scripts/sync-server-skills.mjs",
    "stuck/SKILL.md [paths-user-only] neither provider lets the model load a user-only skill, so its paths rule could never fire; drop disable-model-invocation (BB-NATIVE.md)",
    "",
    "3/7 skills clean, 4 findings",
    "",
  ]);
});

test("a brief that runs a skill gives both the Claude Code and the Codex syntax", () => {
  const run = check({
    "server.ts": 'const SKILL_NAMES = [\n  "a",\n  "b",\n] as const;\n',
    "skills/b/SKILL.md": "---\nname: b\ndescription: x\n---\n",
    "skills/a/SKILL.md": [
      "---",
      "name: a",
      "description: x",
      "---",
      "Start its brief with `/b` on its own line.",
      "",
      "Start its brief with `/b` for a Claude Code child",
      "and `$b` for a Codex child.",
      "",
      "Start its brief with `/b`, or `$b-other` on Codex.",
      "",
      "Start the brief with:",
      "",
      "```text",
      "/b",
      "Do the task.",
      "```",
      "",
      "1. Each brief starting with `/b` or `$b`.",
      "2. Then run `/b` yourself.",
      "3. Use `$b` for a Codex child; for a Claude Code child,",
      "   start its brief with `/b`.",
      "",
      "The worker runs `/b`, and its brief says where to write.",
      "",
      "Each brief starting with `/unknown-skill` is not ours.",
      "",
    ].join("\n"),
  });
  assert.equal(run.status, 1, run.stderr);
  assert.equal(
    run.stdout,
    [
      "a/SKILL.md:5 [brief-prefix] a brief runs /b only on Claude Code; also give $b for a Codex child",
      "a/SKILL.md:10 [brief-prefix] a brief runs /b only on Claude Code; also give $b for a Codex child",
      "a/SKILL.md:12 [brief-prefix] a brief runs /b only on Claude Code; also give $b for a Codex child",
      "",
      "1/2 skills clean, 3 findings",
      "",
    ].join("\n")
  );
});
