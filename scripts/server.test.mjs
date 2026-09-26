// Rerunnable check for the delegation rules server.ts injects: node --test scripts/
import { test } from "node:test";
import assert from "node:assert/strict";

const { default: plugin, delegationRules } = await import("../server.ts");

const PARENTS = { "claude-code": "claude-opus-5-5", codex: "gpt-6-astra" };

// Every skill switch is on, as in a fresh install, except the ones named in `off`.
async function instructions(models, { provider = "claude-code", off = [] } = {}) {
  const values = new Proxy({ skills: true, models }, { get: (target, key) => (key in target ? target[key] : !off.includes(key)) });
  let configure;
  await plugin({
    settings: { define: () => ({ get: async () => values, onChange: () => {} }) },
    agents: { configure: (fn) => (configure = fn) },
    log: { info: () => {} },
  });
  return configure({ provider: { id: provider, model: PARENTS[provider], capabilities: {} } }).instructions;
}

const roleLines = (text) => text.slice(text.indexOf("Role models (provider / model @effort):\n")).split("\n").slice(1);

const TS_LINE = "Before you read or edit a file matching `**/*.ts` or `**/*.tsx`, load the typescript-best-practices skill.";

test("a partial setting overrides only its roles, and inherit-parent becomes the parent's model", async () => {
  const defaults = roleLines(await instructions(""));
  const partial = roleLines(await instructions("# budget: small (medium)\nbug-fix: inherit-parent\narena runners: codex / gpt-6-sol @high, inherit-parent\n"));
  assert.ok(partial.includes("bug-fix: claude-code / claude-opus-5-5"));
  assert.ok(partial.includes("arena runners: codex / gpt-6-sol @high, claude-code / claude-opus-5-5"));
  const untouched = defaults.filter((line) => !/^(bug-fix|arena runners):/.test(line));
  assert.equal(untouched.length, defaults.length - 2);
  assert.deepEqual(partial.filter((line) => untouched.includes(line)), untouched);
});

test("a mapping too long for BB's 4096-character limit is replaced by where to read it", async () => {
  const panel = Array.from({ length: 24 }, () => "claude-code / claude-fable-5-1 @xhigh").join(", ");
  const models = `arena runners: ${panel}\narchitect runners: ${panel}\ninterrogate reviewers: ${panel}\n`;
  for (const provider of Object.keys(PARENTS)) {
    const text = await instructions(models, { provider });
    assert.ok(text.length <= 4096, `${provider}: ${text.length} characters`);
    assert.equal(text.includes("claude-fable-5-1 @xhigh, claude-code"), false);
    assert.match(text, new RegExp(`Run bb plugin config pstack --json\\. .* inherit-parent means ${provider} / ${PARENTS[provider]}\\.$`));
    assert.ok(text.includes(TS_LINE), provider);
  }
});

test("the default mapping is inlined whole on every provider", async () => {
  for (const provider of Object.keys(PARENTS)) {
    const text = await instructions("", { provider });
    assert.ok(text.length <= 4096, `${provider}: ${text.length} characters`);
    assert.match(text, /^interrogate reviewers: .+ @xhigh$/m);
  }
});

test("every provider is told to load a paths skill for matching files", async () => {
  for (const provider of Object.keys(PARENTS)) {
    assert.ok((await instructions("", { provider })).includes(`${TS_LINE}\n\nRole models`), provider);
  }
});

test("user-only skills are out of every skill list, and Codex is told its users run them with $", async () => {
  const codex = await instructions("", { provider: "codex" });
  const claude = await instructions("", { provider: "claude-code" });
  assert.ok(
    codex.includes(
      "Most are user-invoked only, so they are not in your skill list. pstack text writes /<name>; here say and run $<name>, and ask a user who types /<name> for $<name>. Read a named skill"
    )
  );
  assert.ok(claude.includes("Most are user-invoked only, so they are not in your skill list. Read a named skill"));
  assert.equal(claude.includes("$<name>"), false);
});

test("a switched-off skill gets no paths line", async () => {
  for (const provider of Object.keys(PARENTS)) {
    const text = await instructions("", { provider, off: ["typescript-best-practices"] });
    assert.equal(text.includes("Before you read or edit"), false, provider);
  }
});

test("path lines too long to fit give way to one fixed sentence before the role models do, and nothing passes the limit", () => {
  const many = Array.from({ length: 40 }, (_, i) => [`path-skill-${i}`, [`**/*.ext${i}`, `src/**/*.{a${i},b${i}}`]]);
  const panel = Array.from({ length: 24 }, () => "claude-code / claude-fable-5-1 @xhigh").join(", ");
  const long = `arena runners: ${panel}\narchitect runners: ${panel}\ninterrogate reviewers: ${panel}\n`;

  const roomy = delegationRules("codex", "gpt-6-astra", "", many);
  assert.ok(roomy.length <= 4096, `${roomy.length} characters`);
  assert.equal(roomy.includes("path-skill-0"), false);
  assert.match(roomy, /load each pstack skill whose SKILL\.md `paths` globs match it\.\n\nRole models \(provider \/ model @effort\):\n/);

  const tight = delegationRules("codex", "gpt-6-astra", long, many);
  assert.ok(tight.length <= 4096, `${tight.length} characters`);
  assert.match(tight, /load each pstack skill whose SKILL\.md `paths` globs match it\.\n\nThe role models are too long to inline here\. Run bb plugin config pstack --json\./);

  const few = delegationRules("codex", "gpt-6-astra", long, many.slice(0, 1));
  assert.ok(few.includes("load the path-skill-0 skill.\n\nThe role models are too long"), few.slice(-600));

  const claude = delegationRules("claude-code", "claude-opus-5-5", "", many);
  assert.ok(claude.length <= 4096, `${claude.length} characters`);
  assert.match(claude, /load each pstack skill whose SKILL\.md `paths` globs match it\.\n\nRole models \(provider \/ model @effort\):\n/);
});
