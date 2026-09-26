// Rerunnable check for scripts/sync-server-skills.mjs: node --test scripts/
import { test, after } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, copyFileSync, rmSync, existsSync, symlinkSync } from "node:fs";
import { join, dirname } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const SCRIPT = fileURLToPath(new URL("./sync-server-skills.mjs", import.meta.url));
const FRONTMATTER = fileURLToPath(new URL("./frontmatter.mjs", import.meta.url));
const REPO = fileURLToPath(new URL("..", import.meta.url));

function tree(files) {
  const root = mkdtempSync(join(tmpdir(), "sync-server-skills test with spaces-"));
  after(() => rmSync(root, { recursive: true, force: true }));
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), text);
  }
  mkdirSync(join(root, "scripts"));
  copyFileSync(SCRIPT, join(root, "scripts/sync-server-skills.mjs"));
  copyFileSync(FRONTMATTER, join(root, "scripts/frontmatter.mjs"));
  symlinkSync(join(REPO, "node_modules"), join(root, "node_modules"));
  return root;
}

const run = (root, ...args) => spawnSync("node", ["scripts/sync-server-skills.mjs", ...args], { cwd: root, encoding: "utf8" });

function sync(files) {
  const root = tree(files);
  return { root, run: run(root), server: readFileSync(join(root, "server.ts"), "utf8") };
}

const SERVER = [
  "const SKILL_NAMES = [",
  '  "gone",',
  "] as const;",
  "const SKILL_SUMMARIES: Record<SkillName, string> = {",
  '  "gone": "x",',
  "};",
  "const SKILL_PATHS: Partial<Record<SkillName, readonly string[]>> = {",
  '  "gone": ["**/*.x"],',
  "};",
  "",
].join("\n");

const NO_PATHS = "const SKILL_PATHS: Partial<Record<SkillName, readonly string[]>> = {};\n";

test("server.ts lists every skill directory with the first sentence of its description", () => {
  const { run, server } = sync({
    "server.ts": SERVER,
    "skills/b/SKILL.md": "---\nname: b\ndescription: >-\n  Folded over\n  two lines. Then more.\n---\n",
    "skills/a/SKILL.md": '---\nname: a\ndescription: "Does \\"a\\". Then more."\n---\n',
  });
  assert.equal(run.status, 0, run.stderr);
  assert.equal(run.stdout, "updated: server.ts (2 skills)\n");
  assert.equal(
    server,
    'const SKILL_NAMES = [\n  "a",\n  "b",\n] as const;\nconst SKILL_SUMMARIES: Record<SkillName, string> = {\n  "a": "Does \\"a\\".",\n  "b": "Folded over two lines.",\n};\n' +
      NO_PATHS
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
    'const SKILL_NAMES = [\n  "a",\n] as const;\nconst SKILL_SUMMARIES: Record<SkillName, string> = {\n  "a": "Use $& and $1 as they are.",\n};\n' + NO_PATHS
  );
});

test("SKILL_PATHS takes every list form and keeps brace globs whole", () => {
  const { run, server } = sync({
    "server.ts": SERVER,
    "skills/flow/SKILL.md": '---\nname: flow\ndescription: x\npaths: ["**/*.{ts,tsx}", "**/*.md"]\n---\n',
    "skills/lines/SKILL.md": '---\nname: lines\ndescription: x\npaths: [ # python\n  "**/*.py", # sources\n  "**/*.pyi"\n]\n---\n',
    "skills/block/SKILL.md": "---\nname: block\ndescription: x\npaths:\n- \"**/migrations/**\"\n- '*.sql'\n---\n",
    "skills/comma/SKILL.md": "---\nname: comma\ndescription: x\npaths: src/**/*.rs, *.toml\n---\n",
    "skills/none/SKILL.md": "---\nname: none\ndescription: x\n---\n",
  });
  assert.equal(run.status, 0, run.stderr);
  assert.ok(
    server.endsWith(
      [
        "const SKILL_PATHS: Partial<Record<SkillName, readonly string[]>> = {",
        '  "block": ["**/migrations/**", "*.sql"],',
        '  "comma": ["src/**/*.rs", "*.toml"],',
        '  "flow": ["**/*.{ts,tsx}", "**/*.md"],',
        '  "lines": ["**/*.py", "**/*.pyi"],',
        "};",
        "",
      ].join("\n")
    ),
    server
  );
});

test("--check writes nothing and exits 1 while server.ts is out of date", () => {
  const root = tree({
    "server.ts": SERVER,
    "skills/a/SKILL.md": '---\nname: a\ndescription: x\npaths: ["**/*.ts"]\n---\n',
  });
  const stale = run(root, "--check");
  assert.equal(stale.status, 1);
  assert.equal(stale.stdout, "out of date: server.ts\nrun node scripts/sync-server-skills.mjs\n");
  assert.equal(readFileSync(join(root, "server.ts"), "utf8"), SERVER);
  assert.equal(run(root).status, 0);
  assert.deepEqual([run(root, "--check").status, run(root, "--check").stdout], [0, "up to date: 1 skills\n"]);
  assert.equal(existsSync(join(root, "skills/a/agents")), false);
});

test("a server.ts without one of the generated blocks is an error, not a silent skip", () => {
  const root = tree({
    "server.ts": SERVER.slice(0, SERVER.indexOf("const SKILL_PATHS")),
    "skills/a/SKILL.md": "---\nname: a\ndescription: x\n---\n",
  });
  const result = run(root);
  assert.equal(result.status, 2);
  assert.match(result.stderr, /server\.ts has no block matching .*SKILL_PATHS/);
});

test("invalid frontmatter is an error naming the file", () => {
  const root = tree({
    "server.ts": SERVER,
    "skills/broken/SKILL.md": "---\nname: broken\ndescription: a: b: c\n---\n",
  });
  const result = run(root);
  assert.equal(result.status, 2);
  assert.match(result.stderr, /^skills\/broken\/SKILL\.md: invalid frontmatter: /);
  assert.equal(readFileSync(join(root, "server.ts"), "utf8"), SERVER);
});

test("this repository is up to date", () => {
  const result = spawnSync("node", [SCRIPT, "--check"], { cwd: REPO, encoding: "utf8" });
  assert.equal(result.status, 0, result.stdout);
});
