#!/usr/bin/env node
// Apply upstream changes made after the pinned SHA in UPSTREAM (cursor/plugins,
// path pstack/ and each bundle= skill listed there, with its plugin's LICENSE)
// onto this repo with a real 3-way merge, then bump the pin. Run from a clean
// checkout of this repo:
//   node scripts/sync-upstream.mjs            sync to upstream main
//   node scripts/sync-upstream.mjs --to <sha> sync to a specific upstream commit
// Prints one status line first: "up-to-date", "applied" or "conflicts".
// Exit 0 for up-to-date/applied, 2 for conflicts, 1 for errors. Every change is
// read and merged before anything is written, so an error leaves the tree and
// the pin untouched.
import { execFileSync, spawnSync } from "node:child_process";
import { readFileSync, writeFileSync, readdirSync, mkdtempSync, mkdirSync, rmSync, lstatSync, readlinkSync, symlinkSync, chmodSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const PIN_FILE = join(ROOT, "UPSTREAM");
const ALIASED = ["arena", "tdd", "blast-radius"];
// Kept byte for byte as upstream wrote it, so the aliases do not apply.
const VERBATIM = new Set(["UPSTREAM-README.md"]);
const MAX_BUFFER = 256 * 1024 * 1024;

const ABSENT = "000000";
const REGULAR = "100644";
const EXECUTABLE = "100755";
const SYMLINK = "120000";
const SUPPORTED = new Set([REGULAR, EXECUTABLE, SYMLINK]);

const gitBuffer = (...args) => execFileSync("git", args, { cwd: ROOT, maxBuffer: MAX_BUFFER });
const git = (...args) => gitBuffer(...args).toString("utf8").trim();

function readPin() {
  const entries = readFileSync(PIN_FILE, "utf8").split("\n").filter(Boolean).map((line) => line.split("=", 2));
  const fields = Object.fromEntries(entries);
  const bundles = entries.filter(([key]) => key === "bundle").map(([, value]) => parseBundle(value));
  return { repo: fields.repo, path: fields.path, sha: fields.sha, bundles };
}

function parseBundle(path) {
  const [plugin, skills, name, ...rest] = path.split("/");
  if (!plugin || skills !== "skills" || !name || rest.length) throw new Error(`UPSTREAM: bundle=${path} is not <plugin>/skills/<name>`);
  return { path, plugin, name };
}

// Upstream path -> our paths, none to drop the file. Mirrors MANIFEST.md.
function mapPath(upstreamPath, pin) {
  const bundle = pin.bundles.find(({ path }) => upstreamPath.startsWith(path + "/"));
  if (bundle) return [`skills/${bundle.name}/` + upstreamPath.slice(bundle.path.length + 1)];
  const licensed = pin.bundles.filter(({ plugin }) => upstreamPath === `${plugin}/LICENSE`);
  if (licensed.length) return licensed.map(({ name }) => `skills/${name}/LICENSE`);
  if (!upstreamPath.startsWith(pin.path + "/")) return [];
  const p = upstreamPath.slice(pin.path.length + 1);
  if (p.startsWith(".cursor-plugin/") || p.startsWith("automations/")) return [];
  if (p === "agents/poteto-agent.md") return [];
  if (p === "agents/comment-sicko.md") return ["skills/no-comments/references/comment-sicko.md"];
  if (p === "README.md") return ["UPSTREAM-README.md"];
  for (const name of ALIASED) {
    if (p.startsWith(`skills/${name}/`)) return [`skills/pstack-${name}/` + p.slice(`skills/${name}/`.length)];
  }
  return [p];
}

// The pstack- aliases for skills that collide with other installs.
function alias(text) {
  for (const old of ALIASED) {
    const neu = `pstack-${old}`;
    text = text
      .replace(new RegExp(`^name: ${old}$`, "m"), `name: ${neu}`)
      .replace(new RegExp(`\\*\\*${old}\\*\\*`, "g"), `**${neu}**`)
      .replace(new RegExp("`" + old + "`", "g"), "`" + neu + "`")
      .replace(new RegExp(`(?<![\\w/-])/${old}(?![\\w-])`, "g"), `/${neu}`)
      .replace(new RegExp(`skills/${old}/`, "g"), `skills/${neu}/`)
      .replace(new RegExp(`\\.\\./${old}/`, "g"), `../${neu}/`)
      .replace(new RegExp(`\\[${old}\\]\\(`, "g"), `[${neu}](`)
      .replace(new RegExp(`\\bthe ${old} skill`, "g"), `the ${neu} skill`);
  }
  return text;
}

const isText = (path) => /\.(md|ts|mjs|sh|json|txt|lock)$/.test(path) || !/\.[a-z0-9]+$/i.test(path);

// One side of a three-way merge: { mode, content } or null when the file does
// not exist on that side. A symlink's content is its target.
function upstreamSide(mode, sha, upstreamPath, aliased) {
  if (mode === ABSENT) return null;
  if (!SUPPORTED.has(mode)) throw new Error(`${upstreamPath}: unsupported upstream mode ${mode}`);
  const blob = gitBuffer("cat-file", "blob", sha);
  return { mode, content: aliased ? Buffer.from(alias(blob.toString("utf8"))) : blob };
}

// This checkout's side at `ours`, walked one path component at a time so no
// symlink is followed. A directory at `ours`, or a file or symlink where one of
// its parent directories belongs, is no side at all; `inTheWay` lists the files
// that must be deleted before a file can be written there.
function localSide(ours) {
  const parts = ours.split("/");
  for (let depth = 1; depth <= parts.length; depth++) {
    const path = parts.slice(0, depth).join("/");
    const abs = join(ROOT, path);
    let stat;
    try {
      stat = lstatSync(abs);
    } catch (error) {
      if (error.code === "ENOENT") return { side: null };
      throw error;
    }
    const last = depth === parts.length;
    if (stat.isDirectory()) {
      if (last) return { side: null, inTheWay: filesUnder(path) };
      continue;
    }
    if (!last) return { side: null, inTheWay: [path] };
    if (stat.isSymbolicLink()) return { side: { mode: SYMLINK, content: Buffer.from(readlinkSync(abs)) } };
    return { side: { mode: stat.mode & 0o111 ? EXECUTABLE : REGULAR, content: readFileSync(abs) } };
  }
}

const filesUnder = (dir) =>
  readdirSync(join(ROOT, dir), { withFileTypes: true }).flatMap((entry) =>
    entry.isDirectory() ? filesUnder(`${dir}/${entry.name}`) : [`${dir}/${entry.name}`]
  );

// Changed paths in scope with both sides' modes and blobs, from git's own
// metadata: a side is absent only when git says so.
function upstreamChanges(from, to, scope) {
  const fields = gitBuffer("diff", "--raw", "-z", "--no-renames", "--no-abbrev", from, to, "--", ...scope)
    .toString("utf8")
    .split("\0");
  const changes = [];
  for (let i = 0; i + 1 < fields.length; i += 2) {
    const [baseMode, theirsMode, baseSha, theirsSha] = fields[i].slice(1).split(" ");
    changes.push({ path: fields[i + 1], baseMode, theirsMode, baseSha, theirsSha });
  }
  return changes;
}

// Both ends of the range, since a file that moves from a bundle into pstack/
// inside it exists at only one end each.
function checkCollisions(from, to, scope, pin) {
  const paths = new Set(
    [from, to].flatMap((rev) => gitBuffer("ls-tree", "-r", "-z", "--name-only", rev, "--", ...scope).toString("utf8").split("\0").filter(Boolean))
  );
  const sources = new Map();
  for (const path of [...paths].sort()) {
    for (const ours of mapPath(path, pin)) {
      if (sources.has(ours)) throw new Error(`${ours} maps from both ${sources.get(ours)} and ${path}`);
      sources.set(ours, path);
    }
  }
}

const same = (x, y) => x === y || (x !== null && y !== null && x.mode === y.mode && x.content.equals(y.content));
const conflict = (reason, result) => ({ outcome: "conflict", reason, result });

function mergeMode(base, mine, theirs) {
  if (mine === theirs || theirs === base) return mine;
  if (mine === base) return theirs;
  return null;
}

// Decide one file. Returns the outcome and the side to write: null deletes the
// file, undefined leaves it as it is. Writes nothing.
function mergeFile(ours, base, mine, theirs, scratch) {
  if (theirs === null) {
    if (mine === null) return { outcome: "unchanged" };
    if (same(mine, base)) return { outcome: "deleted", result: null };
    return conflict("changed here, deleted upstream");
  }
  if (mine === null) {
    if (base === null) return { outcome: "added", result: theirs };
    return conflict("deleted here, changed upstream");
  }
  if (same(mine, base)) return { outcome: "updated", result: theirs };

  const mode = mergeMode(base?.mode ?? null, mine.mode, theirs.mode);
  if (mode === null) return conflict("mode changed on both sides");
  const textual = isText(ours) && ![base, mine, theirs].some((side) => side?.mode === SYMLINK);
  if (!textual) {
    if (mine.content.equals(theirs.content) || (base && theirs.content.equals(base.content))) return { outcome: "merged", result: { mode, content: mine.content } };
    if (base && mine.content.equals(base.content)) return { outcome: "merged", result: { mode, content: theirs.content } };
    return conflict("binary or symlink changed on both sides, left as ours");
  }

  const basePath = join(scratch, "base");
  const theirsPath = join(scratch, "theirs");
  writeFileSync(basePath, base?.content ?? "");
  writeFileSync(theirsPath, theirs.content);
  const merged = spawnSync("git", ["merge-file", "-p", "-L", "ours", "-L", "upstream-base", "-L", "upstream", join(ROOT, ours), basePath, theirsPath], { cwd: ROOT, maxBuffer: MAX_BUFFER });
  if (merged.error) throw merged.error;
  if (merged.status === null || merged.status > 127) throw new Error(`git merge-file failed on ${ours}: ${merged.stderr}`);
  const result = { mode, content: merged.stdout };
  return merged.status === 0 ? { outcome: "merged", result } : conflict("edited on both sides, conflict markers in the file", result);
}

// A directory still at `abs` holds no files by now: planning turned any write
// into a conflict while a file in its way was kept.
function write(abs, side) {
  rmSync(abs, { recursive: true, force: true });
  if (side === null) return;
  mkdirSync(dirname(abs), { recursive: true });
  if (side.mode === SYMLINK) {
    symlinkSync(side.content.toString("utf8"), abs);
    return;
  }
  writeFileSync(abs, side.content);
  chmodSync(abs, side.mode === EXECUTABLE ? 0o755 : 0o644);
}

function main() {
  const toFlag = process.argv.indexOf("--to");
  const pin = readPin();
  const scope = [
    `${pin.path}/`,
    ...pin.bundles.map(({ path }) => `${path}/`),
    ...new Set(pin.bundles.map(({ plugin }) => `${plugin}/LICENSE`)),
  ];
  if (git("status", "--porcelain")) throw new Error("working tree is not clean");

  git("fetch", "--quiet", "--no-tags", pin.repo, "main:refs/upstream/main");
  const to = toFlag > -1 ? git("rev-parse", process.argv[toFlag + 1]) : git("rev-parse", "refs/upstream/main");
  const commits = git("log", "--format=%h %s", `${pin.sha}..${to}`, "--", ...scope);

  if (!commits) {
    console.log(`up-to-date: no changes between ${pin.sha.slice(0, 7)} and ${to.slice(0, 7)} in ${scope.join(", ")}`);
    return 0;
  }
  checkCollisions(pin.sha, to, scope, pin);

  const scratch = mkdtempSync(join(tmpdir(), "pstack-sync-"));
  const plan = [];
  const dropped = [];
  try {
    for (const change of upstreamChanges(pin.sha, to, scope)) {
      const targets = mapPath(change.path, pin);
      if (!targets.length) dropped.push(change.path);
      for (const ours of targets) {
        const aliased = isText(ours) && !VERBATIM.has(ours);
        const base = upstreamSide(change.baseMode, change.baseSha, change.path, aliased);
        const theirs = upstreamSide(change.theirsMode, change.theirsSha, change.path, aliased);
        const { side, inTheWay } = localSide(ours);
        plan.push({ ours, inTheWay, ...mergeFile(ours, base, side, theirs, scratch) });
      }
    }
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }

  // Upstream can turn a file into a directory or back. The new path is free
  // only if this sync deletes everything in its way; a kept file blocks it.
  const deleted = new Set(plan.filter((file) => file.result === null).map((file) => file.ours));
  for (const file of plan) {
    const kept = file.result && file.inTheWay?.find((path) => !deleted.has(path));
    if (kept) Object.assign(file, conflict(`${kept} is kept here and is in the way`));
  }

  // Deletions first, so a path that changed type is free before it is written.
  for (const { ours, result } of plan) if (result === null) write(join(ROOT, ours), null);
  for (const { ours, result } of plan) if (result) write(join(ROOT, ours), result);
  writeFileSync(PIN_FILE, readFileSync(PIN_FILE, "utf8").replace(/^sha=.*$/m, `sha=${to}`));

  const conflicts = plan.filter((file) => file.outcome === "conflict").map((file) => `${file.ours} (${file.reason})`);
  const lines = plan.map((file) => `${file.outcome.padEnd(9)} ${file.ours}${file.reason ? ` (${file.reason})` : ""}`);
  console.log(`${conflicts.length ? "conflicts" : "applied"}: ${pin.sha.slice(0, 7)}..${to.slice(0, 7)} in ${scope.join(", ")}`);
  console.log(`\nupstream commits:\n${commits}`);
  console.log(`\nfiles:\n${lines.join("\n") || "(none)"}`);
  if (dropped.length) console.log(`\ndropped (not shipped on BB):\n${dropped.join("\n")}`);
  if (conflicts.length) console.log(`\nconflicts to resolve:\n${conflicts.join("\n")}`);
  return conflicts.length ? 2 : 0;
}

try {
  process.exit(main());
} catch (error) {
  console.error(`error: ${error.message}`);
  process.exit(1);
}
