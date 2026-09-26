#!/usr/bin/env node
// Gate for the BB-native contract (BB-NATIVE.md). Run from the repo root:
//   node scripts/check-bb-native.mjs            all skills
//   node scripts/check-bb-native.mjs how why    only these skill dirs
// Exits 1 when any skill has a finding.
import { readdirSync, readFileSync, statSync, existsSync } from "node:fs";
import { join, dirname, resolve, relative, extname } from "node:path";
import { fileURLToPath } from "node:url";
import { parse } from "yaml";
import { frontmatter, isUserOnly, paths } from "./frontmatter.mjs";

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

// A brief that makes a child run a skill must use the child's provider syntax:
// Claude Code runs `/<name>`, Codex `$<name>` (BB-NATIVE.md). Where the text
// says how a brief starts, its paragraph and a fenced brief right after it
// must give `$<skill>` for every `/<skill>` they run.
const BRIEF_START =
  /\b(start|begin)(s|ning|ing)?\s+(its|the|each|a|every|that)?\s*brief\b|\bbriefs?\s+(start|begin)(s|ning|ing)?\b|\bbriefs?\b[^.]{0,40}\bfirst line\b/i;
const SLASH_SKILL = /(?:^|[\s`(])\/([a-z][a-z0-9-]*)(?=[`\s.,;:)]|$)/gm;
const FENCE = /^\s*(```|~~~)/;
const NEW_BLOCK = /^(\s*(\d+\.|[-*+])\s|#)/;

// The lines that say how a brief starts: from the matching line to the end of
// its paragraph or list item, plus a fenced block that follows it (after blank
// lines).
function briefWindow(lines, from) {
  let end = from;
  const continues = (line) => line.trim() !== "" && !FENCE.test(line) && !NEW_BLOCK.test(line);
  while (end + 1 < lines.length && continues(lines[end + 1])) end++;
  let next = end + 1;
  while (next < lines.length && lines[next].trim() === "") next++;
  if (next < lines.length && FENCE.test(lines[next])) {
    end = next;
    while (end + 1 < lines.length && !FENCE.test(lines[end + 1])) end++;
    end = Math.min(end + 1, lines.length - 1);
  }
  return lines.slice(from, end + 1).join("\n");
}

function briefPrefixFindings(lines) {
  const findings = [];
  lines.forEach((line, i) => {
    if (!BRIEF_START.test(line)) return;
    const window = briefWindow(lines, i);
    const names = new Set([...window.matchAll(SLASH_SKILL)].map((m) => m[1]));
    for (const name of names) {
      if (!existsSync(join(SKILLS, name, "SKILL.md"))) continue;
      if (new RegExp(`\\$${name}(?![a-z0-9-])`).test(window)) continue;
      findings.push({ line: i + 1, text: `[brief-prefix] a brief runs /${name} only on Claude Code; also give $${name} for a Codex child` });
    }
  });
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

// Claude Code hides a disable-model-invocation skill from the model; Codex
// ignores the flag and reads agents/openai.yaml instead, so the two must agree.
// The injected rules load a `paths` skill for matching files on every provider,
// but neither provider lets the model load a hidden skill, so a skill cannot
// be both (BB-NATIVE.md).
function invocationFindings(name, text) {
  const policy = join(SKILLS, name, "agents", "openai.yaml");
  let fm;
  let hiddenFromCodex;
  try {
    fm = frontmatter(text);
    hiddenFromCodex = existsSync(policy) && parse(readFileSync(policy, "utf8"))?.policy?.allow_implicit_invocation === false;
  } catch (error) {
    return [`${name} [yaml] invalid SKILL.md frontmatter or agents/openai.yaml: ${error.message.split("\n")[0]}`];
  }
  const userOnly = isUserOnly(fm);
  const findings = [];
  if (userOnly !== hiddenFromCodex) {
    findings.push(`${name}/agents/openai.yaml [codex-policy] must set allow_implicit_invocation: false exactly when SKILL.md sets disable-model-invocation: true; run node scripts/sync-server-skills.mjs`);
  }
  if (userOnly && paths(fm).length > 0) {
    findings.push(`${name}/SKILL.md [paths-user-only] neither provider lets the model load a user-only skill, so its paths rule could never fire; drop disable-model-invocation (BB-NATIVE.md)`);
  }
  return findings;
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

  const skillText = readFileSync(skillMd, "utf8");
  const fm = frontmatterName(skillText);
  if (fm !== name) findings.push(`${name}/SKILL.md: frontmatter name "${fm}" must equal the directory name`);
  for (const finding of invocationFindings(name, skillText)) findings.push(finding);

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
    for (const { line, text } of briefPrefixFindings(lines)) findings.push(`${rel}:${line} ${text}`);
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
