// Rerunnable check for the delegation rules server.ts injects: node --test scripts/
import { test } from "node:test";
import assert from "node:assert/strict";

const plugin = (await import("../server.ts")).default;

async function instructions(models) {
  let configure;
  await plugin({
    settings: { define: () => ({ get: async () => ({ skills: true, models }), onChange: () => {} }) },
    agents: { configure: (fn) => (configure = fn) },
    log: { info: () => {} },
  });
  return configure({ provider: { id: "claude-code", model: "claude-opus-5-5", capabilities: {} } }).instructions;
}

const roleLines = (text) => text.slice(text.indexOf("Role models (provider / model @effort):\n")).split("\n").slice(1);

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
  const text = await instructions(`arena runners: ${panel}\narchitect runners: ${panel}\ninterrogate reviewers: ${panel}\n`);
  assert.ok(text.length <= 4096, `${text.length} characters`);
  assert.equal(text.includes("claude-fable-5-1 @xhigh, claude-code"), false);
  assert.match(text, /Run bb plugin config pstack --json\. .* inherit-parent means claude-code \/ claude-opus-5-5\.$/);
});

test("the default mapping is inlined whole", async () => {
  const text = await instructions("");
  assert.ok(text.length <= 4096, `${text.length} characters`);
  assert.match(text, /^interrogate reviewers: .+ @xhigh$/m);
});
