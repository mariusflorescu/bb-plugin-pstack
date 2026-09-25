// Rerunnable check for scripts/sync-upstream.mjs: node --test scripts/
// Each case builds a throwaway upstream repo and a throwaway copy of this repo,
// then runs the real script between two upstream commits.
import { test, after } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, copyFileSync, chmodSync, symlinkSync, lstatSync, readlinkSync, existsSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { tmpdir } from "node:os";

const SCRIPT = new URL("./sync-upstream.mjs", import.meta.url).pathname;
const ENV = {
  ...process.env,
  GIT_CONFIG_GLOBAL: "/dev/null",
  GIT_CONFIG_NOSYSTEM: "1",
  GIT_AUTHOR_NAME: "t",
  GIT_AUTHOR_EMAIL: "t@t",
  GIT_COMMITTER_NAME: "t",
  GIT_COMMITTER_EMAIL: "t@t",
};

const git = (cwd, ...args) => execFileSync("git", args, { cwd, env: ENV, encoding: "utf8" }).trim();

// files: path -> "text" | { text, exec } | { link } | { gitlink } | null (delete)
function commit(root, files, prefix = "") {
  const gitlinks = [];
  for (const [path, value] of Object.entries(files)) {
    const spec = typeof value === "string" ? { text: value } : value;
    const abs = join(root, prefix + path);
    rmSync(abs, { force: true });
    if (spec === null) continue;
    if (spec.gitlink) {
      gitlinks.push(prefix + path);
      continue;
    }
    mkdirSync(dirname(abs), { recursive: true });
    if (spec.link) {
      symlinkSync(spec.link, abs);
      continue;
    }
    writeFileSync(abs, spec.text);
    chmodSync(abs, spec.exec ? 0o755 : 0o644);
  }
  git(root, "add", "-A");
  for (const path of gitlinks) git(root, "update-index", "--add", "--cacheinfo", `160000,${git(root, "rev-parse", "HEAD")},${path}`);
  git(root, "commit", "-qm", "commit");
  return git(root, "rev-parse", "HEAD");
}

function sync({ base, upstream, ours }) {
  const dir = mkdtempSync(join(tmpdir(), "sync-upstream-test-"));
  after(() => rmSync(dir, { recursive: true, force: true }));
  const up = join(dir, "upstream");
  const me = join(dir, "ours");
  mkdirSync(up);
  git(up, "init", "-q", "-b", "main");
  const from = commit(up, base, "pstack/");
  const to = commit(up, upstream, "pstack/");
  mkdirSync(join(me, "scripts"), { recursive: true });
  git(me, "init", "-q", "-b", "main");
  copyFileSync(SCRIPT, join(me, "scripts/sync-upstream.mjs"));
  writeFileSync(join(me, "UPSTREAM"), `repo=${up}\npath=pstack\nsha=${from}\n`);
  commit(me, ours);
  const run = spawnSync("node", ["scripts/sync-upstream.mjs", "--to", to], { cwd: me, env: ENV, encoding: "utf8" });
  const at = (path) => join(me, path);
  return { run, from, to, at, dir: me };
}

const mode = (abs) => (lstatSync(abs).mode & 0o777).toString(8);

test("a file deleted here stays deleted and conflicts when upstream edits it", () => {
  const { run, at } = sync({
    base: { "skills/gone/SKILL.md": "one\n" },
    upstream: { "skills/gone/SKILL.md": "two\n" },
    ours: { "README.md": "ours\n" },
  });
  assert.equal(run.status, 2, run.stderr);
  assert.match(run.stdout, /^conflict +skills\/gone\/SKILL\.md \(deleted here, changed upstream\)$/m);
  assert.equal(existsSync(at("skills/gone/SKILL.md")), false);
});

test("executable bits, mode-only changes and symlinks follow upstream", () => {
  const base = {
    "skills/tool/scripts/watch": { text: "#!/bin/sh\necho watch\n", exec: true },
    "skills/tool/scripts/chmod-me": "#!/bin/sh\necho hi\n",
    "skills/tool/SKILL.md": "tool\n",
  };
  const { run, at } = sync({
    base,
    upstream: {
      "skills/tool/scripts/watch": null,
      "skills/tool/scripts/watch-pr": { text: "#!/bin/sh\necho watch\n", exec: true },
      "skills/tool/scripts/chmod-me": { text: "#!/bin/sh\necho hi\n", exec: true },
      "skills/tool/current": { link: "SKILL.md" },
    },
    ours: base,
  });
  assert.equal(run.status, 0, run.stderr);
  assert.match(run.stdout, /^deleted +skills\/tool\/scripts\/watch$/m);
  assert.match(run.stdout, /^added +skills\/tool\/scripts\/watch-pr$/m);
  assert.match(run.stdout, /^updated +skills\/tool\/scripts\/chmod-me$/m);
  assert.equal(existsSync(at("skills/tool/scripts/watch")), false);
  assert.equal(mode(at("skills/tool/scripts/watch-pr")), "755");
  assert.equal(mode(at("skills/tool/scripts/chmod-me")), "755");
  assert.equal(lstatSync(at("skills/tool/current")).isSymbolicLink(), true);
  assert.equal(readlinkSync(at("skills/tool/current")), "SKILL.md");
});

test("edits on both sides of a text file merge, with the pstack- aliases applied", () => {
  const { run, at } = sync({
    base: { "skills/m/SKILL.md": "a\nb\nc\nd\ne\n" },
    upstream: { "skills/m/SKILL.md": "a\nb\nc\nd\nsee **arena**\n" },
    ours: { "skills/m/SKILL.md": "A\nb\nc\nd\ne\n" },
  });
  assert.equal(run.status, 0, run.stderr);
  assert.match(run.stdout, /^merged +skills\/m\/SKILL\.md$/m);
  assert.equal(readFileSync(at("skills/m/SKILL.md"), "utf8"), "A\nb\nc\nd\nsee **pstack-arena**\n");
});

test("an entry it cannot apply aborts before any write and keeps the pin", () => {
  const { run, from, at, dir } = sync({
    base: { "skills/a/SKILL.md": "one\n" },
    upstream: { "skills/a/SKILL.md": "two\n", "vendor": { gitlink: true } },
    ours: { "skills/a/SKILL.md": "one\n" },
  });
  assert.equal(run.status, 1);
  assert.match(run.stderr, /^error: pstack\/vendor: unsupported upstream mode 160000$/m);
  assert.equal(readFileSync(at("skills/a/SKILL.md"), "utf8"), "one\n");
  assert.equal(readFileSync(at("UPSTREAM"), "utf8").match(/^sha=(.*)$/m)[1], from);
  assert.equal(git(dir, "status", "--porcelain"), "");
});
