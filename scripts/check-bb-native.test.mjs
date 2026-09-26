// Rerunnable check for scripts/check-bb-native.mjs: node --test scripts/
import { test, after } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, copyFileSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const SCRIPT = fileURLToPath(new URL("./check-bb-native.mjs", import.meta.url));

function check(files) {
  const root = mkdtempSync(join(tmpdir(), "check-bb-native test with spaces-"));
  after(() => rmSync(root, { recursive: true, force: true }));
  for (const [path, text] of Object.entries({ "scripts/check-bb-native.mjs": null, ...files })) {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    if (text === null) copyFileSync(SCRIPT, join(root, path));
    else writeFileSync(join(root, path), text);
  }
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
      "Walk `bb thread list --parent-thread <id> --include-hidden`, not `bb thread list --project x`.",
      "Walk `bb thread list --parent-thread <id>`.",
      "Re-read `git show origin/main:pstack/skills/swarm/SKILL.md`, and `git show origin/main:docs/verify.md` for the project.",
      'Pin it with `--base-branch "$(git rev-parse HEAD)"`, or `--base-branch origin/<branch>` elsewhere. Omitting `--base-branch` uses the default.',
      "Stack it with `--new-environment worktree --base-branch <parent branch>`.",
      "",
    ].join("\n"),
  });
  assert.equal(run.status, 1, run.stderr);
  assert.equal(
    run.stdout,
    [
      "a/SKILL.md:5 [wait-error] a failed child is in status error and bb thread wait exits at once; read bb thread log <id>: If a child never reaches idle, drop it.",
      'a/SKILL.md:7 [provider-host] pass --environment "$BB_ENVIRONMENT_ID" or --machine; without one bb reads the server\'s machine: Run `bb provider models codex --json`.',
      "a/SKILL.md:9 [hidden-children] add --include-hidden, or hidden children are skipped: Walk `bb thread list --parent-thread <id>`.",
      "a/SKILL.md:10 [trunk-read] re-read pstack from trunk with poteto-mode's scripts/read-from-trunk.sh skills/<path>: Re-read `git show origin/main:pstack/skills/swarm/SKILL.md`, and `git show origin/main:docs/verify.md` for the project.",
      'a/SKILL.md:12 [base-branch] pin a worktree to "$(git rev-parse HEAD)" after committing, or to a pushed origin/<branch>; a local branch moves: Stack it with `--new-environment worktree --base-branch <parent branch>`.',
      "",
      "0/1 skills clean, 5 findings",
      "",
    ].join("\n")
  );
});
