// Rerunnable check for scripts/sync-server-skills.mjs: node --test scripts/
import { test, after } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, copyFileSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const SCRIPT = fileURLToPath(new URL("./sync-server-skills.mjs", import.meta.url));

function sync(files) {
  const root = mkdtempSync(join(tmpdir(), "sync-server-skills test with spaces-"));
  after(() => rmSync(root, { recursive: true, force: true }));
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), text);
  }
  mkdirSync(join(root, "scripts"));
  copyFileSync(SCRIPT, join(root, "scripts/sync-server-skills.mjs"));
  const run = spawnSync("node", ["scripts/sync-server-skills.mjs"], { cwd: root, encoding: "utf8" });
  return { run, server: readFileSync(join(root, "server.ts"), "utf8") };
}

const SERVER = 'const SKILL_NAMES = [\n  "gone",\n] as const;\nconst SKILL_SUMMARIES: Record<SkillName, string> = {\n  "gone": "x",\n};\n';

test("server.ts lists every skill directory with the first sentence of its description", () => {
  const { run, server } = sync({
    "server.ts": SERVER,
    "skills/b/SKILL.md": "---\nname: b\ndescription: >-\n  Folded over\n  two lines. Then more.\n---\n",
    "skills/a/SKILL.md": '---\nname: a\ndescription: "Does \\"a\\". Then more."\n---\n',
  });
  assert.equal(run.status, 0, run.stderr);
  assert.equal(run.stdout, "server.ts updated: 2 skills\n");
  assert.equal(
    server,
    'const SKILL_NAMES = [\n  "a",\n  "b",\n] as const;\nconst SKILL_SUMMARIES: Record<SkillName, string> = {\n  "a": "Does \\"a\\".",\n  "b": "Folded over two lines.",\n};\n'
  );
});

test("a description with replacement syntax such as $& is written literally", () => {
  const { run, server } = sync({
    "server.ts": SERVER,
    "skills/a/SKILL.md": "---\nname: a\ndescription: Use $& and $1 as they are.\n---\n",
  });
  assert.equal(run.status, 0, run.stderr);
  assert.equal(
    server,
    'const SKILL_NAMES = [\n  "a",\n] as const;\nconst SKILL_SUMMARIES: Record<SkillName, string> = {\n  "a": "Use $& and $1 as they are.",\n};\n'
  );
});
