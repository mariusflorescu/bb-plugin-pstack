// Rerunnable check for scripts/sync-upstream.mjs: node --test scripts/
// Each case builds a throwaway upstream repo and a throwaway copy of this repo,
// then runs the real script between two upstream commits.
import { test, after } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, copyFileSync, chmodSync, symlinkSync, lstatSync, readlinkSync, existsSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const REPO = fileURLToPath(new URL("..", import.meta.url));
const SCRIPT = join(REPO, "scripts/sync-upstream.mjs");
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
    rmSync(abs, { recursive: true, force: true });
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

function sync({ base, upstream, ours, bundles = [], prefix = "pstack/" }) {
  const dir = mkdtempSync(join(tmpdir(), "sync-upstream test with spaces-"));
  after(() => rmSync(dir, { recursive: true, force: true }));
  const up = join(dir, "upstream");
  const me = join(dir, "ours");
  mkdirSync(up);
  git(up, "init", "-q", "-b", "main");
  const from = commit(up, base, prefix);
  const to = commit(up, upstream, prefix);
  mkdirSync(join(me, "scripts"), { recursive: true });
  git(me, "init", "-q", "-b", "main");
  copyFileSync(SCRIPT, join(me, "scripts/sync-upstream.mjs"));
  writeFileSync(join(me, "UPSTREAM"), `repo=${up}\npath=pstack\nsha=${from}\n${bundles.map((path) => `bundle=${path}\n`).join("")}`);
  commit(me, ours);
  const run = spawnSync("node", ["scripts/sync-upstream.mjs", "--to", to], { cwd: me, env: ENV, encoding: "utf8" });
  const at = (path) => join(me, path);
  return { run, up, from, to, at, dir: me };
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

test("the upstream README lands verbatim, without the pstack- aliases", () => {
  const { run, at } = sync({
    base: { "README.md": "run /arena\n" },
    upstream: { "README.md": "run /arena or [/tdd](./skills/tdd/SKILL.md)\n" },
    ours: { "UPSTREAM-README.md": "run /arena\n" },
  });
  assert.equal(run.status, 0, run.stderr);
  assert.match(run.stdout, /^updated +UPSTREAM-README\.md$/m);
  assert.equal(readFileSync(at("UPSTREAM-README.md"), "utf8"), "run /arena or [/tdd](./skills/tdd/SKILL.md)\n");
});

test("this repo's UPSTREAM-README.md is the pinned upstream README, byte for byte", (t) => {
  const pin = readFileSync(join(REPO, "UPSTREAM"), "utf8");
  const blob = `${pin.match(/^sha=(.*)$/m)[1]}:${pin.match(/^path=(.*)$/m)[1]}/README.md`;
  const upstream = spawnSync("git", ["cat-file", "blob", blob], { cwd: REPO, encoding: "utf8" });
  if (upstream.status !== 0) return t.skip(`${blob} is not fetched here; node scripts/sync-upstream.mjs fetches upstream`);
  assert.equal(readFileSync(join(REPO, "UPSTREAM-README.md"), "utf8"), upstream.stdout);
});

const pinned = (at) => readFileSync(at("UPSTREAM"), "utf8").match(/^sha=(.*)$/m)[1];

test("upstream turning a file into a directory deletes the file, then adds the directory", () => {
  const { run, to, at } = sync({
    base: { "skills/x/references/topic.md": "flat\n" },
    upstream: { "skills/x/references/topic.md": null, "skills/x/references/topic.md/index.md": "nested\n" },
    ours: { "skills/x/references/topic.md": "flat\n" },
  });
  assert.equal(run.status, 0, run.stderr);
  assert.match(run.stdout, /^deleted +skills\/x\/references\/topic\.md$/m);
  assert.match(run.stdout, /^added +skills\/x\/references\/topic\.md\/index\.md$/m);
  assert.equal(readFileSync(at("skills/x/references/topic.md/index.md"), "utf8"), "nested\n");
  assert.equal(pinned(at), to);
});

test("upstream turning a directory into a file deletes the directory, then adds the file", () => {
  const { run, to, at } = sync({
    base: { "skills/x/references/topic.md/index.md": "nested\n" },
    upstream: { "skills/x/references/topic.md/index.md": null, "skills/x/references/topic.md": "flat\n" },
    ours: { "skills/x/references/topic.md/index.md": "nested\n" },
  });
  assert.equal(run.status, 0, run.stderr);
  assert.match(run.stdout, /^deleted +skills\/x\/references\/topic\.md\/index\.md$/m);
  assert.match(run.stdout, /^added +skills\/x\/references\/topic\.md$/m);
  assert.equal(readFileSync(at("skills/x/references/topic.md"), "utf8"), "flat\n");
  assert.equal(pinned(at), to);
});

test("a file edited here that upstream turned into a directory stays, and the directory conflicts", () => {
  const { run, to, at } = sync({
    base: { "skills/x/references/topic.md": "flat\n" },
    upstream: { "skills/x/references/topic.md": null, "skills/x/references/topic.md/index.md": "nested\n" },
    ours: { "skills/x/references/topic.md": "flat, adapted for BB\n" },
  });
  assert.equal(run.status, 2, run.stderr);
  assert.match(run.stdout, /^conflict +skills\/x\/references\/topic\.md \(changed here, deleted upstream\)$/m);
  assert.match(run.stdout, /^conflict +skills\/x\/references\/topic\.md\/index\.md \(skills\/x\/references\/topic\.md is kept here and is in the way\)$/m);
  assert.equal(readFileSync(at("skills/x/references/topic.md"), "utf8"), "flat, adapted for BB\n");
  assert.equal(pinned(at), to);
});

test("a directory holding a file edited here that upstream turned into a file stays, and the file conflicts", () => {
  const { run, to, at } = sync({
    base: { "skills/x/references/topic.md/index.md": "nested\n" },
    upstream: { "skills/x/references/topic.md/index.md": null, "skills/x/references/topic.md": "flat\n" },
    ours: { "skills/x/references/topic.md/index.md": "nested, adapted for BB\n" },
  });
  assert.equal(run.status, 2, run.stderr);
  assert.match(run.stdout, /^conflict +skills\/x\/references\/topic\.md\/index\.md \(changed here, deleted upstream\)$/m);
  assert.match(run.stdout, /^conflict +skills\/x\/references\/topic\.md \(skills\/x\/references\/topic\.md\/index\.md is kept here and is in the way\)$/m);
  assert.equal(readFileSync(at("skills/x/references/topic.md/index.md"), "utf8"), "nested, adapted for BB\n");
  assert.equal(pinned(at), to);
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

test("bundle= lines survive the pin bump", () => {
  const { run, up, to, at } = sync({
    bundles: ["cursor-team-kit/skills/deslop", "cursor-team-kit/skills/what-did-i-get-done"],
    base: { "skills/a/SKILL.md": "one\n" },
    upstream: { "skills/a/SKILL.md": "two\n" },
    ours: { "skills/a/SKILL.md": "one\n" },
  });
  assert.equal(run.status, 0, run.stderr);
  assert.equal(readFileSync(at("skills/a/SKILL.md"), "utf8"), "two\n");
  assert.equal(
    readFileSync(at("UPSTREAM"), "utf8"),
    `repo=${up}\npath=pstack\nsha=${to}\nbundle=cursor-team-kit/skills/deslop\nbundle=cursor-team-kit/skills/what-did-i-get-done\n`
  );
});

test("a bundle= line that is not <plugin>/skills/<name> aborts before any write", () => {
  const { run, up, from, at } = sync({
    bundles: ["cursor-team-kit/deslop"],
    base: { "skills/a/SKILL.md": "one\n" },
    upstream: { "skills/a/SKILL.md": "two\n" },
    ours: { "skills/a/SKILL.md": "one\n" },
  });
  assert.equal(run.status, 1);
  assert.equal(run.stderr, "error: UPSTREAM: bundle=cursor-team-kit/deslop is not <plugin>/skills/<name>\n");
  assert.equal(readFileSync(at("skills/a/SKILL.md"), "utf8"), "one\n");
  assert.equal(readFileSync(at("UPSTREAM"), "utf8"), `repo=${up}\npath=pstack\nsha=${from}\nbundle=cursor-team-kit/deslop\n`);
});
