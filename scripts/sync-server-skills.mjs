#!/usr/bin/env node
// Regenerate SKILL_NAMES, SKILL_SUMMARIES and SKILL_PATHS in server.ts from each
// skills/<name>/SKILL.md frontmatter. Run after adding, removing or
// re-describing a skill: node scripts/sync-server-skills.mjs
// With --check it writes nothing and exits 1 when server.ts is out of date.
import { readdirSync, readFileSync, writeFileSync, statSync, existsSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { frontmatter, description, paths as pathsOf } from "./frontmatter.mjs";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const SKILLS = join(ROOT, "skills");
const SERVER = join(ROOT, "server.ts");
const MAX = 150;
const CHECK = process.argv.includes("--check");

function summary(fm) {
  const value = description(fm);
  const first = value.match(/^.*?[.!?](?=\s|$)/)?.[0] ?? value;
  return first.length > MAX ? first.slice(0, MAX - 3).trimEnd() + "..." : first;
}

function readFrontmatter(name) {
  try {
    return frontmatter(readFileSync(join(SKILLS, name, "SKILL.md"), "utf8"));
  } catch (error) {
    console.error(`skills/${name}/SKILL.md: invalid frontmatter: ${error.message.split("\n")[0]}`);
    process.exit(2);
  }
}

const names = readdirSync(SKILLS)
  .filter((d) => !d.startsWith(".") && statSync(join(SKILLS, d)).isDirectory() && existsSync(join(SKILLS, d, "SKILL.md")))
  .sort();
const fms = new Map(names.map((n) => [n, readFrontmatter(n)]));

const list = names.map((n) => `  ${JSON.stringify(n)},`).join("\n");
const summaries = names.map((n) => `  ${JSON.stringify(n)}: ${JSON.stringify(summary(fms.get(n)))},`).join("\n");
const paths = names
  .map((n) => [n, pathsOf(fms.get(n))])
  .filter(([, globs]) => globs.length > 0)
  .map(([n, globs]) => `  ${JSON.stringify(n)}: [${globs.map((g) => JSON.stringify(g)).join(", ")}],`)
  .join("\n");

// Replacer functions, so a `$&` or `$1` in a description stays literal.
const BLOCKS = [
  [/const SKILL_NAMES = \[[\s\S]*?\] as const;/, () => `const SKILL_NAMES = [\n${list}\n] as const;`],
  [/const SKILL_SUMMARIES: Record<SkillName, string> = \{[\s\S]*?\n\};/, () => `const SKILL_SUMMARIES: Record<SkillName, string> = {\n${summaries}\n};`],
  [
    /const SKILL_PATHS: Partial<Record<SkillName, readonly string\[\]>> = \{(?:\n[\s\S]*?\n)?\};/,
    () => `const SKILL_PATHS: Partial<Record<SkillName, readonly string[]>> = {${paths ? `\n${paths}\n` : ""}};`,
  ],
];

const src = readFileSync(SERVER, "utf8");
let next = src;
for (const [pattern, replacement] of BLOCKS) {
  if (!pattern.test(next)) {
    console.error(`server.ts has no block matching ${pattern}`);
    process.exit(2);
  }
  next = next.replace(pattern, replacement);
}

if (CHECK) {
  console.log(next === src ? `up to date: ${names.length} skills` : "out of date: server.ts\nrun node scripts/sync-server-skills.mjs");
  process.exit(next === src ? 0 : 1);
}
if (next !== src) writeFileSync(SERVER, next);
console.log(next === src ? `up to date: ${names.length} skills` : `updated: server.ts (${names.length} skills)`);
