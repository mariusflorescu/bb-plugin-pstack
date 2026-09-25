#!/usr/bin/env node
// Apply upstream pstack changes (cursor/plugins, path pstack/) made after the
// pinned SHA in UPSTREAM onto this repo with a real 3-way merge, then bump the
// pin. Run from a clean checkout of this repo:
//   node scripts/sync-upstream.mjs            sync to upstream main
//   node scripts/sync-upstream.mjs --to <sha> sync to a specific upstream commit
// Prints one status line first: "up-to-date", "applied" or "conflicts".
// Exit 0 for up-to-date/applied, 2 for conflicts, 1 for errors.
import { execFileSync, spawnSync } from "node:child_process";
import { readFileSync, writeFileSync, existsSync, mkdtempSync, mkdirSync, rmSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import { tmpdir } from "node:os";

const ROOT = resolve(dirname(new URL(import.meta.url).pathname), "..");
const PIN_FILE = join(ROOT, "UPSTREAM");
const ALIASED = ["arena", "tdd", "blast-radius"];

const git = (...args) => execFileSync("git", args, { cwd: ROOT, encoding: "utf8", maxBuffer: 256 * 1024 * 1024 }).trim();

function readPin() {
  const fields = Object.fromEntries(
    readFileSync(PIN_FILE, "utf8").split("\n").filter(Boolean).map((line) => line.split("=", 2))
  );
  return { repo: fields.repo, path: fields.path, sha: fields.sha };
}

// Upstream path -> our path, or null to drop the file. Mirrors MANIFEST.md.
function mapPath(upstreamPath, prefix) {
  if (!upstreamPath.startsWith(prefix + "/")) return null;
  const p = upstreamPath.slice(prefix.length + 1);
  if (p.startsWith(".cursor-plugin/") || p.startsWith("automations/")) return null;
  if (p === "agents/poteto-agent.md") return null;
  if (p === "agents/comment-sicko.md") return "skills/no-comments/references/comment-sicko.md";
  if (p === "README.md") return "UPSTREAM-README.md";
  for (const name of ALIASED) {
    if (p.startsWith(`skills/${name}/`)) return `skills/pstack-${name}/` + p.slice(`skills/${name}/`.length);
  }
  return p;
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

function upstreamBlob(sha, path) {
  try {
    return execFileSync("git", ["show", `${sha}:${path}`], { cwd: ROOT, maxBuffer: 256 * 1024 * 1024 });
  } catch {
    return null;
  }
}

// Three-way merge of one upstream file onto ours. Base and theirs get the
// aliases first, so alias renames never show up as conflicts.
function mergeFile(ours, baseBuf, theirsBuf, scratch) {
  const abs = join(ROOT, ours);
  const text = isText(ours);
  const base = baseBuf && text ? alias(baseBuf.toString("utf8")) : baseBuf;
  const theirs = theirsBuf && text ? alias(theirsBuf.toString("utf8")) : theirsBuf;
  const mine = existsSync(abs) ? readFileSync(abs) : null;
  const same = (x, y) => x !== null && y !== null && Buffer.compare(Buffer.from(x), Buffer.from(y)) === 0;

  if (theirs === null) {
    if (mine === null) return "unchanged";
    if (same(mine, base)) {
      rmSync(abs);
      return "deleted";
    }
    return "conflict";
  }
  if (mine === null || same(mine, base) || !text) {
    if (mine !== null && !text && !same(mine, base) && !same(mine, theirs)) return "conflict";
    mkdirSync(dirname(abs), { recursive: true });
    writeFileSync(abs, theirs);
    return mine === null ? "added" : "updated";
  }
  const basePath = join(scratch, "base");
  const theirsPath = join(scratch, "theirs");
  writeFileSync(basePath, base ?? "");
  writeFileSync(theirsPath, theirs);
  const result = spawnSync("git", ["merge-file", "-L", "ours", "-L", "upstream-base", "-L", "upstream", abs, basePath, theirsPath], { cwd: ROOT });
  return result.status === 0 ? "merged" : "conflict";
}

function main() {
  const toFlag = process.argv.indexOf("--to");
  const pin = readPin();
  if (git("status", "--porcelain")) throw new Error("working tree is not clean");

  git("fetch", "--quiet", "--no-tags", pin.repo, "main:refs/upstream/main");
  const to = toFlag > -1 ? git("rev-parse", process.argv[toFlag + 1]) : git("rev-parse", "refs/upstream/main");
  const commits = git("log", "--format=%h %s", `${pin.sha}..${to}`, "--", pin.path);

  if (!commits) {
    console.log(`up-to-date: no ${pin.path}/ changes between ${pin.sha.slice(0, 7)} and ${to.slice(0, 7)}`);
    return 0;
  }

  const scratch = mkdtempSync(join(tmpdir(), "pstack-sync-"));
  const changed = git("diff", "--name-only", "--no-renames", pin.sha, to, "--", pin.path + "/").split("\n").filter(Boolean);
  const results = { conflict: [], dropped: [] };
  const lines = [];
  for (const upstreamPath of changed) {
    const ours = mapPath(upstreamPath, pin.path);
    if (ours === null) {
      results.dropped.push(upstreamPath);
      continue;
    }
    const outcome = mergeFile(ours, upstreamBlob(pin.sha, upstreamPath), upstreamBlob(to, upstreamPath), scratch);
    lines.push(`${outcome.padEnd(9)} ${ours}`);
    if (outcome === "conflict") results.conflict.push(ours);
  }
  const conflicts = results.conflict;
  const dropped = results.dropped;

  writeFileSync(PIN_FILE, `repo=${pin.repo}\npath=${pin.path}\nsha=${to}\n`);

  console.log(`${conflicts.length ? "conflicts" : "applied"}: ${pin.sha.slice(0, 7)}..${to.slice(0, 7)}`);
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
