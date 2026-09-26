#!/usr/bin/env node
// Regenerate SKILL_NAMES and SKILL_SUMMARIES in server.ts from each
// skills/<name>/SKILL.md frontmatter. Run after adding, removing or
// re-describing a skill: node scripts/sync-server-skills.mjs
import { readdirSync, readFileSync, writeFileSync, statSync, existsSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const SKILLS = join(ROOT, "skills");
const SERVER = join(ROOT, "server.ts");
const MAX = 150;

function parseDoubleQuoted(raw) {
  try {
    return JSON.parse(raw);
  } catch {
    return raw.slice(1, -1).replace(/\\"/g, '"');
  }
}

// A block scalar (`>-`, `|` and the like) keeps its text on the indented lines
// below the key. Folding every line break to a space is enough for a summary.
function descriptionValue(frontmatter) {
  const lines = frontmatter.split("\n");
  const at = lines.findIndex((line) => line.startsWith("description:"));
  if (at === -1) return "";
  const raw = lines[at].slice("description:".length).trim();
  if (/^[>|][+-]?$/.test(raw)) {
    const body = [];
    for (const line of lines.slice(at + 1)) {
      if (line.trim() !== "" && !/^\s/.test(line)) break;
      body.push(line.trim());
    }
    return body.join(" ").replace(/\s+/g, " ").trim();
  }
  return raw.startsWith('"') ? parseDoubleQuoted(raw) : raw.replace(/^'(.*)'$/, "$1").replace(/''/g, "'");
}

function description(text) {
  const value = descriptionValue(text.match(/^---\n([\s\S]*?)\n---/)?.[1] ?? "");
  const first = value.match(/^.*?[.!?](?=\s|$)/)?.[0] ?? value;
  return first.length > MAX ? first.slice(0, MAX - 3).trimEnd() + "..." : first;
}

const names = readdirSync(SKILLS)
  .filter((d) => !d.startsWith(".") && statSync(join(SKILLS, d)).isDirectory() && existsSync(join(SKILLS, d, "SKILL.md")))
  .sort();

const list = names.map((n) => `  ${JSON.stringify(n)},`).join("\n");
const summaries = names
  .map((n) => `  ${JSON.stringify(n)}: ${JSON.stringify(description(readFileSync(join(SKILLS, n, "SKILL.md"), "utf8")))},`)
  .join("\n");

// Replacer functions, so a `$&` or `$1` in a description stays literal.
const src = readFileSync(SERVER, "utf8");
const next = src
  .replace(/const SKILL_NAMES = \[[\s\S]*?\] as const;/, () => `const SKILL_NAMES = [\n${list}\n] as const;`)
  .replace(/const SKILL_SUMMARIES: Record<SkillName, string> = \{[\s\S]*?\n\};/, () => `const SKILL_SUMMARIES: Record<SkillName, string> = {\n${summaries}\n};`);

if (next === src) {
  console.log(`server.ts already lists ${names.length} skills`);
} else {
  writeFileSync(SERVER, next);
  console.log(`server.ts updated: ${names.length} skills`);
}
