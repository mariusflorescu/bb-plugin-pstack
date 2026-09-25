#!/usr/bin/env node
// Gate for the BB-native contract (BB-NATIVE.md). Run from the repo root:
//   node scripts/check-bb-native.mjs            all skills
//   node scripts/check-bb-native.mjs how why    only these skill dirs
// Exits 1 when any skill has a finding.
import { readdirSync, readFileSync, statSync, existsSync } from "node:fs";
import { join, dirname, resolve, relative, extname } from "node:path";

const ROOT = resolve(dirname(new URL(import.meta.url).pathname), "..");
const SKILLS = join(ROOT, "skills");

// Cursor mechanisms that must not survive in shipped skill text. Each row is
// one contract line from BB-NATIVE.md.
const RULES = [
  { id: "cursor-name", re: /\bcursor\b(?!\/plugins)/i, hint: "name the BB mechanism instead of Cursor" },
  { id: "cursor-path", re: /~?\/?\.cursor\//, hint: "no ~/.cursor paths; use bb thread log / $BB_THREAD_STORAGE" },
  { id: "task-tool", re: /\bsubagent_type\b|`Task`|\bTask (call|tool)|\bTask\(|run_in_background|is_background|generalPurpose/, hint: "a subagent is `bb thread spawn --parent-self`" },
  { id: "readonly-flag", re: /readonly:\s*true|readonly strips/, hint: "say read-only in the child's brief" },
  { id: "ask-question", re: /\bAskQuestion\b/, hint: "say 'ask the user'" },
  { id: "model-slug", re: /\bgrok-\d|claude-opus-5-5-max|\bcomposer-\d/i, hint: "name the role, not a model slug" },
  { id: "team-kit", re: /cursor-team-kit|\bcontrol-(ui|cli)\b|\bcreate-skill\b/, hint: "use the project's verification skill, bb browser/terminals, skill-creator" },
  { id: "transcripts", re: /agent-transcripts/, hint: "use bb thread log / bb thread output" },
  { id: "origin-forge", re: /\bOrigin\b|`origin pr|origin pr (create|view|merge|edit|ready|checks|thread)|command -v origin/, hint: "gh is the only forge" },
  { id: "loop-cmd", re: /(^|[\s`(])\/loop\b/, hint: "background bb thread wait, or bb automation create" },
  { id: "cloud-agent", re: /cloud[- ](agent|VM|root|sleeper)|environment: "cloud"|Cursor dashboard/i, hint: "--new-environment worktree or --machine" },
  { id: "persona-dir", re: /\.\.\/(\.\.\/)?agents\//, hint: "personas live in the owning skill's references/" },
];

const TEXT = new Set([".md", ".sh", ".mjs", ".ts", ".json", ".txt", ""]);
// Code files may legitimately say "cursor" (pagination) or talk to GitHub bots.
const CODE_EXEMPT = new Set(["cursor-name", "origin-forge", "task-tool"]);

function walk(dir) {
  return readdirSync(dir).flatMap((entry) => {
    if (entry === "node_modules" || entry === "bun.lock") return [];
    const path = join(dir, entry);
    return statSync(path).isDirectory() ? walk(path) : [path];
  });
}

function frontmatterName(text) {
  const block = text.match(/^---\n([\s\S]*?)\n---/);
  return block?.[1].match(/^name:\s*(.+)$/m)?.[1].trim().replace(/^["']|["']$/g, "") ?? null;
}

function relativeTargets(text) {
  const targets = [];
  for (const m of text.matchAll(/\]\(([^)\s#]+)(#[^)]*)?\)/g)) targets.push(m[1]);
  for (const m of text.matchAll(/`((?:\.\.\/|\.\/)[^`\s]+)`/g)) targets.push(m[1]);
  return targets.filter((t) => /[./]/.test(t) && !/^[a-z]+:/i.test(t) && !t.includes("<") && !t.startsWith("/"));
}

function checkSkill(name) {
  const dir = join(SKILLS, name);
  const findings = [];
  const skillMd = join(dir, "SKILL.md");
  if (!existsSync(skillMd)) return [`${name}: missing SKILL.md`];

  const fm = frontmatterName(readFileSync(skillMd, "utf8"));
  if (fm !== name) findings.push(`${name}/SKILL.md: frontmatter name "${fm}" must equal the directory name`);

  for (const file of walk(dir)) {
    if (!TEXT.has(extname(file))) continue;
    const rel = relative(SKILLS, file);
    const isMarkdown = extname(file) === ".md";
    const lines = readFileSync(file, "utf8").split("\n");
    lines.forEach((line, i) => {
      for (const rule of RULES) {
        if (!isMarkdown && CODE_EXEMPT.has(rule.id)) continue;
        if (rule.re.test(line)) findings.push(`${rel}:${i + 1} [${rule.id}] ${rule.hint}: ${line.trim().slice(0, 140)}`);
      }
    });
    if (!isMarkdown) continue;
    for (const target of relativeTargets(lines.join("\n"))) {
      const abs = resolve(dirname(file), target.replace(/[.,;:]+$/, ""));
      if (!abs.startsWith(SKILLS + "/")) findings.push(`${rel} [link-escape] ${target} points outside skills/ (not shipped to threads)`);
      else if (!existsSync(abs)) findings.push(`${rel} [link-missing] ${target} does not exist`);
    }
  }
  return findings;
}

function checkServerList(dirs) {
  const src = readFileSync(join(ROOT, "server.ts"), "utf8");
  const literal = src.match(/SKILL_NAMES = \[([\s\S]*?)\] as const/)?.[1] ?? "";
  const listed = new Set([...literal.matchAll(/"([^"]+)"/g)].map((m) => m[1]));
  const findings = [];
  for (const d of dirs) if (!listed.has(d)) findings.push(`server.ts: SKILL_NAMES is missing "${d}"`);
  for (const l of listed) if (!dirs.includes(l)) findings.push(`server.ts: SKILL_NAMES lists "${l}" with no skills/${l}/`);
  return findings;
}

const allDirs = readdirSync(SKILLS).filter((d) => statSync(join(SKILLS, d)).isDirectory()).sort();
const selected = process.argv.slice(2);
const targets = selected.length ? selected : allDirs;
const findings = targets.flatMap(checkSkill);
if (!selected.length) findings.push(...checkServerList(allDirs));

for (const f of findings) console.log(f);
const dirty = new Set(findings.map((f) => f.split(/[/:\s]/)[0]));
console.log(`\n${targets.length - [...dirty].filter((d) => targets.includes(d)).length}/${targets.length} skills clean, ${findings.length} findings`);
process.exit(findings.length ? 1 : 0);
