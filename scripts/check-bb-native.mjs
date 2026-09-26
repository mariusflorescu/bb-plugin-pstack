#!/usr/bin/env node
// Gate for the BB-native contract (BB-NATIVE.md). Run from the repo root:
//   node scripts/check-bb-native.mjs            all skills
//   node scripts/check-bb-native.mjs how why    only these skill dirs
// Exits 1 when any skill has a finding.
import { readdirSync, readFileSync, statSync, existsSync } from "node:fs";
import { join, dirname, resolve, relative, extname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
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
  { id: "cursor-rules", re: /\.mdc\b|alwaysApply|always-applied rule/, hint: "bb config is the plugin setting, .bb/AGENTS.md or .bb/skills" },
  { id: "cursor-ui", re: /\bcomposer\b|background agent|\bagent mode\b/i, hint: "name the bb surface (thread, child thread, worktree)" },
  { id: "persona-dir", re: /\.\.\/(\.\.\/)?agents\//, hint: "personas live in the owning skill's references/" },
  { id: "wait-error", re: /never reach(es|ed)? idle|wait (times|timed) out/i, hint: "a failed child is in status error and bb thread wait exits at once; read bb thread log <id>" },
  // Each listing on its own: the flag must sit in the same command, before a closing backtick or shell separator.
  // In a shell script only a call counts, not a mention in a comment or a quoted message.
  {
    id: "hidden-children",
    re: /bb thread list\b(?![^`|;&\n]*--include-hidden)/,
    shell: /^(?!\s*#)(?:[^"']*(?:"[^"]*"|'[^']*'))*[^"']*?\bbb thread list\b(?![^`|;&\n]*--include-hidden)/,
    hint: "add --include-hidden, or hidden threads are skipped",
  },
  { id: "trunk-read", re: /origin\/main:pstack\//, hint: "re-read pstack from trunk with poteto-mode's scripts/read-from-trunk.sh skills/<path>" },
  // A line that itself names a pinned form (a ref resolved with "$(git rev-parse <ref>)", or origin/<branch>) already says how to pin.
  { id: "base-branch", re: /--base-branch(?!`)/, unless: /rev-parse HEAD|\$\(git rev-parse [^)]+\)|origin\//, hint: "pin a worktree to \"$(git rev-parse HEAD)\" after committing, or to a pushed origin/<branch>; a local branch moves" },
  { id: "provider-host", re:/bb provider (list|models)\b(?!.*--(environment|machine|host)\b)/, hint: "pass --environment \"$BB_ENVIRONMENT_ID\" or --machine; without one bb reads the server's machine" },
  // The failure paragraph of a fan-out skill: an overloaded or rate-limited child restarts by itself.
  { id: "retry-check", re: /\bstatus `?error\b/, unless: /provider-retry/, hint: "run the provider-retry check in the pstack delegation rules before counting a failed child out" },
];

const TEXT = new Set([".md", ".sh", ".mjs", ".ts", ".json", ".txt", ""]);
// Code files may legitimately say "cursor" (pagination) or talk to GitHub bots,
// and the failure paragraph a skill tells the agent to follow is prose.
const CODE_EXEMPT = new Set(["cursor-name", "origin-forge", "task-tool", "retry-check"]);

// A bold name is a skill reference when it carries a pstack prefix or the text
// calls it a skill ("the **how** skill", "**a** and **b** principle skills").
// Other bold words (**evidence**) are emphasis.
const BOLD_NAME = /\*\*([a-z][a-z0-9-]*)\*\*/g;
const CALLED_A_SKILL = /^\*\*[a-z][a-z0-9-]*\*\*((,|,? and|,? or) \*\*[a-z][a-z0-9-]*\*\*)* (principle )?skills?\b/;
// Skills BB's own guide plugin ships, which pstack text may name.
const BB_SKILLS = new Set(["skill-creator"]);

// The lookup the injected delegation rules describe: ../<name>/, or
// ../principle-<name>/ for a principle named without its prefix.
const resolvesToSkill = (name) =>
  BB_SKILLS.has(name) || [name, `principle-${name}`].some((dir) => existsSync(join(SKILLS, dir, "SKILL.md")));

function skillNameFindings(line) {
  const findings = [];
  for (const m of line.matchAll(BOLD_NAME)) {
    const name = m[1];
    const isReference = /^(principle|pstack)-/.test(name) || CALLED_A_SKILL.test(line.slice(m.index));
    if (isReference && !resolvesToSkill(name)) findings.push(`[skill-name] **${name}** has no skills/${name}/ or skills/principle-${name}/`);
  }
  return findings;
}

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
    const isShell = [".sh", ""].includes(extname(file));
    const lines = readFileSync(file, "utf8").split("\n");
    lines.forEach((line, i) => {
      for (const rule of RULES) {
        if (!isMarkdown && CODE_EXEMPT.has(rule.id)) continue;
        const re = (isShell && rule.shell) || rule.re;
        if (re.test(line) && !rule.unless?.test(line)) findings.push(`${rel}:${i + 1} [${rule.id}] ${rule.hint}: ${line.trim().slice(0, 140)}`);
      }
      if (isMarkdown) for (const finding of skillNameFindings(line)) findings.push(`${rel}:${i + 1} ${finding}`);
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

const allDirs = readdirSync(SKILLS).filter((d) => !d.startsWith(".") && statSync(join(SKILLS, d)).isDirectory()).sort();
const selected = process.argv.slice(2);
const targets = selected.length ? selected : allDirs;
const findings = targets.flatMap(checkSkill);
if (!selected.length) findings.push(...checkServerList(allDirs));

for (const f of findings) console.log(f);
const dirty = new Set(findings.map((f) => f.split(/[/:\s]/)[0]));
console.log(`\n${targets.length - [...dirty].filter((d) => targets.includes(d)).length}/${targets.length} skills clean, ${findings.length} findings`);
process.exit(findings.length ? 1 : 0);
