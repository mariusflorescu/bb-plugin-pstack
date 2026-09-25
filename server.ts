// bb-plugin-pstack - the pstack skill library, delivered as a BB plugin.
//
// Every skills/<name>/SKILL.md in this package is imported by the manifest
// (bb.skills) and becomes a plugin-tier skill: a slash command plus an entry
// in the agent skill list on every provider. bb.agents.configure() then
// selects which of those names are active for each thread resolution, which
// is what makes the settings below a master switch plus one switch per skill.
//
// Upstream: cursor/plugins pstack, MIT, (c) 2026 Lauren Tan. See README.md and
// MANIFEST.md for the pinned commit and the adaptations applied.
import type { BbPluginApi, PluginSettingDescriptor } from "@get-bb/plugin-sdk";

// Literal on purpose: a renamed or removed skill fails this plugin's selection
// closed (bb rejects unknown names), instead of silently dropping it.
const SKILL_NAMES = [
  "architect",
  "automate-me",
  "bro",
  "create-verification-skill",
  "figure-it-out",
  "how",
  "interrogate",
  "maintain-verification-skill",
  "make-bot-ui",
  "no-comments",
  "poteto-mode",
  "principle-attack-the-premise",
  "principle-boundary-discipline",
  "principle-build-the-lever",
  "principle-encode-lessons-in-structure",
  "principle-exhaust-the-design-space",
  "principle-experience-first",
  "principle-fix-root-causes",
  "principle-foundational-thinking",
  "principle-guard-the-context-window",
  "principle-laziness-protocol",
  "principle-make-operations-idempotent",
  "principle-migrate-callers-then-delete-legacy-apis",
  "principle-minimize-reader-load",
  "principle-model-the-domain",
  "principle-never-block-on-the-human",
  "principle-outcome-oriented-execution",
  "principle-prove-it-works",
  "principle-redesign-from-first-principles",
  "principle-separate-before-serializing-shared-state",
  "principle-sequence-verifiable-units",
  "principle-subtract-before-you-add",
  "principle-test-behavior-not-implementation",
  "principle-type-system-discipline",
  "pstack-arena",
  "pstack-blast-radius",
  "pstack-tdd",
  "recall",
  "reflect",
  "setup-pstack",
  "show-me-your-work",
  "swarm",
  "teach",
  "technical-writing",
  "typescript-best-practices",
  "unslop",
  "why",
] as const;

type SkillName = (typeof SKILL_NAMES)[number];

// First sentence of each skill's frontmatter description, for the settings UI.
const SKILL_SUMMARIES: Record<SkillName, string> = {
  "architect": "Sketch types, signatures, and module structure before code, then stay in the loop while implementation fills in.",
  "automate-me": "Use for \"automate me\", \"create/update/refresh my -mode skill\", \"turn/capture my preferences or working style into a skill\", or wanting agents to fo...",
  "bro": "Restate the last message in plain human language, with no jargon.",
  "create-verification-skill": "Generate a project-local verification skill that drives your app the way a user does — any language, framework, or platform.",
  "figure-it-out": "Design an auditable playbook when no narrower one fits: a large migration, an ambitious multi-part change, or work a human reviews after stepping a...",
  "how": "Use for \"how does X work\", code walkthroughs before changing something, and placement / ownership / layering questions (\"where should this live\", \"...",
  "interrogate": "Use for \"interrogate\", \"adversarial review\", \"multi-model review\", \"challenge this\", \"stress test this code\", \"find blind spots\", or \"tear this apa...",
  "maintain-verification-skill": "Periodic pass that keeps a project's verification skill and feature map honest: parallel source readers per feature, one live session driving every...",
  "make-bot-ui": "Use when building a custom UI (page, dashboard, buttons) that should wake an agent over a webhook, when the sender runs on another machine and need...",
  "no-comments": "Spawn Comment Sicko, fix accepted findings, and offer encodings for claimed constraints.",
  "poteto-mode": "poteto's agent style for concise, detailed responses, deliberate subagents, unslopped prose, simple code, and verified work.",
  "principle-attack-the-premise": "Apply when two or more fixes that share one premise have failed the same gate.",
  "principle-boundary-discipline": "Apply when wiring validation, error handling, or framework adapters.",
  "principle-build-the-lever": "Apply to any non-trivial work, not just bulk work: edits, migrations, analyses, checks.",
  "principle-encode-lessons-in-structure": "Apply when you catch yourself writing the same instruction a second time, or notice a recurring correction.",
  "principle-exhaust-the-design-space": "Apply when facing a novel UI interaction or architectural decision with no precedent in the codebase.",
  "principle-experience-first": "Apply when product, UX, or feature-scope tradeoffs come up.",
  "principle-fix-root-causes": "Apply when debugging.",
  "principle-foundational-thinking": "Apply before writing logic: choosing core types and data structures, sequencing scaffold-vs-feature work, asking what concurrent actors share.",
  "principle-guard-the-context-window": "Apply when context is filling up: large outputs, long files, repeated reads, fan-out planning.",
  "principle-laziness-protocol": "Apply when refactoring, evaluating diff size, or tempted to add abstractions, layers, or signal threading.",
  "principle-make-operations-idempotent": "Apply when designing commands, lifecycle steps, or processing loops that run amid crashes, restarts, and retries.",
  "principle-migrate-callers-then-delete-legacy-apis": "Apply when introducing a new internal API while old callers still exist.",
  "principle-minimize-reader-load": "Apply when reviewing or shaping code that's hard to trace.",
  "principle-model-the-domain": "Apply when writing stateful logic, or when code branches a lot or repeats a shape assumption across files.",
  "principle-never-block-on-the-human": "Apply when tempted to ask 'should I do X?' on reversible work.",
  "principle-outcome-oriented-execution": "Apply during planned rewrites and migrations with explicit phase boundaries.",
  "principle-prove-it-works": "Apply after completing a task, before declaring done.",
  "principle-redesign-from-first-principles": "Apply when integrating a new requirement into an existing design.",
  "principle-separate-before-serializing-shared-state": "Apply when concurrent actors might write to the same file, branch, key, or state object.",
  "principle-sequence-verifiable-units": "Apply to multi-step work (sweeps, migrations, runs of similar edits) and to how you stack commits and PRs.",
  "principle-subtract-before-you-add": "Apply when sequencing an addition, refactor, or rewrite.",
  "principle-test-behavior-not-implementation": "Apply when you write, change, or keep a test.",
  "principle-type-system-discipline": "Apply when designing types, reviewing a function signature, or writing code in any statically-typed language.",
  "pstack-arena": "Spawn N parallel candidates at the same task, pick a base, graft the strongest parts of the losers into it.",
  "pstack-blast-radius": "Find what a change could break somewhere else before it ships, beyond the diff, and prove the one fact it's safe because of by running real code in...",
  "pstack-tdd": "Use only when the user explicitly asks for TDD, a failing test, or a regression test, OR when the bug has an obvious cheap local test target.",
  "recall": "Reconstruct your recent working context from your own chat history, live state, and the shared record (user reports, prior fixes, incidents), then...",
  "reflect": "Spawn three parallel review subagents over the active transcript, surface learnings, and route each to a concrete edit on an existing skill.",
  "setup-pstack": "Configure which models pstack uses per role and at what reasoning budget.",
  "show-me-your-work": "Keep a reviewable decision trail for long-running or unattended work: a TSV log with one row per decision (what, why, evidence, result).",
  "swarm": "Fan out N parallel workers, drain them, and return one report.",
  "teach": "Explain a body of work plainly so a person actually understands it.",
  "technical-writing": "Layered technical-writing standard: Diátaxis structure, Google developer style sentences, STE instruction rules, Global English syntax.",
  "typescript-best-practices": "TypeScript best practices.",
  "unslop": "Cut AI tells from any writing.",
  "why": "Use for 'why does X work this way', 'why we picked Y', design rationale, regressions, postmortems, or data-backed thresholds.",
};

// Default role mapping. The `models` setting overrides it one role at a time:
// a role the setting leaves out keeps its line here.
const DEFAULT_MODELS = `feature, refactoring: claude-code / claude-opus-5-5 @xhigh
bug-fix: claude-code / claude-fable-5-1 @xhigh
perf-issue: claude-code / claude-fable-5-1 @xhigh
hillclimb: claude-code / claude-fable-5-1 @xhigh
judgment and prose: claude-code / claude-opus-5-5 @xhigh
hardest tasks: claude-code / claude-fable-5-1 @xhigh
how explorer: codex / gpt-6-luna @high
how explainer: claude-code / claude-opus-5-5 @xhigh
why investigators: codex / gpt-6-luna @high
why synthesizer: claude-code / claude-opus-5-5 @xhigh
reflect tooling: claude-code / claude-opus-5-5 @xhigh
reflect judgment, divergent, synthesizer: claude-code / claude-fable-5-1 @xhigh
swarm workers: claude-code / claude-opus-5-5 @high
arena runners: claude-code / claude-opus-5-5 @xhigh, claude-code / claude-fable-5-1 @xhigh, codex / gpt-6-astra @xhigh, codex / gpt-6-sol @xhigh
arena cross-judge pool: codex / gpt-6-astra @xhigh, claude-code / claude-fable-5-1 @xhigh
architect runners: claude-code / claude-opus-5-5 @xhigh, claude-code / claude-fable-5-1 @xhigh, codex / gpt-6-astra @xhigh, codex / gpt-6-sol @xhigh
interrogate reviewers: claude-code / claude-opus-5-5 @xhigh, claude-code / claude-fable-5-1 @xhigh, codex / gpt-6-astra @xhigh, codex / gpt-6-sol @xhigh`;

// Provider-native subagent tools that must not stand in for a pstack role.
const NATIVE_SUBAGENT_TOOLS: Record<string, string> = {
  "claude-code": "the Agent / Explore / Task tool",
  codex: "Codex's built-in subagents",
};

// A role whose entry is this runs on the parent thread's own provider and model.
const INHERIT_PARENT = "inherit-parent";

// BB truncates a plugin's instructions past this many characters.
const INSTRUCTIONS_LIMIT = 4096;

function parseModels(text: string): Map<string, string[]> {
  const roles = new Map<string, string[]>();
  for (const line of text.split("\n")) {
    const match = line.trim().match(/^([^#:][^:]*):\s*(\S.*)$/);
    if (match) roles.set(match[1].trim(), match[2].split(",").map((entry) => entry.trim()));
  }
  return roles;
}

function roleModels(setting: string, parent: string): string {
  const roles = new Map([...parseModels(DEFAULT_MODELS), ...parseModels(setting)]);
  return [...roles]
    .map(([role, entries]) => `${role}: ${entries.map((entry) => (entry === INHERIT_PARENT ? parent : entry)).join(", ")}`)
    .join("\n");
}

function rules(providerId: string, model: string, roleSection: string): string {
  const nativeTool = NATIVE_SUBAGENT_TOOLS[providerId] ?? "the provider's built-in subagent tool";
  return `## pstack delegation rules

You run on ${providerId} / ${model}. When a pstack skill says spawn, delegate, subagent, runner, reviewer, explorer or worker, that is a BB child thread:

bb thread spawn --project "$BB_PROJECT_ID" --parent-self --environment "$BB_ENVIRONMENT_ID" --provider <provider> --model <model> --reasoning-level <effort> --title "<role>: <slice>" --prompt-file <brief>

Take provider, model and effort from the role's line below; an entry without @effort omits --reasoning-level. Never use ${nativeTool} for a pstack role: it runs the wrong model and cannot reach other providers. Panel roles spawn one child per list entry. A child that writes code in parallel with others gets --new-environment worktree --base-branch "$(git rev-parse HEAD)" instead of --environment. Commit what it needs before spawning it, because uncommitted changes do not reach a worktree. A worktree child on another machine (--machine) cannot see your local commits: push first and pass --base-branch origin/<your branch>. A read-only child says so in its brief. Spawn every child of a step before waiting on any, then collect them in one background command:

for id in <ids>; do bb thread wait "$id" --timeout 30m && bb thread output "$id"; done

A child that fails is in status error, and bb thread wait exits at once with an unreachable error instead of timing out. Read why with bb thread log <id> --format minimal. If its model or effort was rejected, pick a same-family model and a listed effort from bb provider models <provider> --environment "$BB_ENVIRONMENT_ID" --json, respawn that seat with the same brief, and say so in your report. Any other failure is a dropout.

Children also report back to this thread. Follow up with bb thread tell <id>. For a cross-judge, take the first pool entry whose model family differs from yours.

pstack skills name each other in bold (for example **unslop**, **principle-prove-it-works**). Most are user-invoked only, so your skill tool will not load them. Read a named skill at ../<name>/SKILL.md from the base directory of the skill that names it. A principle named without its prefix (**prove-it-works** principle skill) is at ../principle-<name>/SKILL.md.

${roleSection}`;
}

// The block every thread receives. A mapping too long to fit whole is replaced
// by where to read it, so BB's truncation never cuts an entry in half.
function delegationRules(providerId: string, model: string, setting: string): string {
  const inline = rules(providerId, model, `Role models (provider / model @effort):\n${roleModels(setting, `${providerId} / ${model}`)}`);
  if (inline.length <= INSTRUCTIONS_LIMIT) return inline;
  return rules(
    providerId,
    model,
    `The role models are too long to inline here. Run bb plugin config pstack --json. values.models has one "role: provider / model @effort" line per role, and a role missing from it uses its line in schema.models.default. ${INHERIT_PARENT} means ${providerId} / ${model}.`
  );
}

export default async function plugin(bb: BbPluginApi) {
  const descriptors: Record<string, PluginSettingDescriptor> = {
    skills: {
      type: "boolean",
      label: "pstack skills",
      description:
        "Master switch for the whole pstack set below. Off contributes no pstack skills to new agent sessions.",
      default: true,
    },
  };
  for (const name of SKILL_NAMES) {
    descriptors[name] = {
      type: "boolean",
      label: name,
      description: SKILL_SUMMARIES[name],
      default: true,
    };
  }

  descriptors.models = {
    type: "string",
    label: "Role models",
    description:
      "One `role: provider / model @effort` line per pstack role; panel roles take a comma-separated list. A role left out keeps its default, and `inherit-parent` runs the role on the parent thread's own provider and model. Written by /setup-pstack. Injected into every thread as the pstack delegation rules.",
    experimental_multiline: true,
    default: DEFAULT_MODELS,
  };

  const settings = bb.settings.define(descriptors);
  let current = await settings.get();
  settings.onChange((next) => {
    current = next;
  });

  bb.agents.configure((context) => {
    if (current.skills !== true) return { tools: [], skills: [] };
    return {
      tools: [],
      skills: SKILL_NAMES.filter((name) => current[name] === true),
      instructions: delegationRules(
        context.provider.id,
        context.provider.model,
        typeof current.models === "string" ? current.models : ""
      ),
    };
  });

  const enabled = SKILL_NAMES.filter((name) => current[name] === true).length;
  bb.log.info(
    `loaded: pstack skills ${current.skills === true ? `on (${enabled}/${SKILL_NAMES.length})` : "off"}`
  );
}
