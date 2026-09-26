// Rerunnable check for the delegation rules server.ts injects: node --test scripts/
import { test } from "node:test";
import assert from "node:assert/strict";

const plugin = (await import("../server.ts")).default;

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
    assert.equal(text.includes(TS_LINE), provider === "codex");
  }
});

test("the default mapping is inlined whole on every provider", async () => {
  for (const provider of Object.keys(PARENTS)) {
    const text = await instructions("", { provider });
    assert.ok(text.length <= 4096, `${provider}: ${text.length} characters`);
    assert.match(text, /^interrogate reviewers: .+ @xhigh$/m);
  }
});

test("a provider that ignores paths frontmatter is told to load the skill for matching files", async () => {
  assert.ok((await instructions("", { provider: "codex" })).includes(`${TS_LINE}\n\nRole models`));
  assert.equal((await instructions("", { provider: "claude-code" })).includes("Before you read or edit"), false);
});

test("a switched-off skill gets no paths line", async () => {
  const text = await instructions("", { provider: "codex", off: ["typescript-best-practices"] });
  assert.equal(text.includes("Before you read or edit"), false);
});
