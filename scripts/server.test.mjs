// Rerunnable check for the delegation rules server.ts injects: node --test scripts/
import { test } from "node:test";
import assert from "node:assert/strict";

const { default: plugin, delegationRules, POTETO_NOTES } = await import("../server.ts");

const PARENTS = { "claude-code": "claude-opus-5-5", codex: "gpt-6-astra" };

// Every skill switch is on, as in a fresh install, except the ones named in `off`.
async function load({ models = "", off = [], storedMetadata = {}, threads = {} } = {}) {
  const values = new Proxy({ skills: !off.includes("skills"), models }, { get: (target, key) => (key in target ? target[key] : !off.includes(key)) });
  const seen = { reads: [], writes: [], published: [], warnings: [] };
  const state = { storedMetadata };
  const registered = {};
  await plugin({
    settings: { define: () => ({ get: async () => values, onChange: () => {} }) },
    agents: { configure: (fn) => (registered.configure = fn) },
    experimental_hooks: { on: (hook, fn) => (registered[hook] = fn) },
    sdk: {
      threads: {
        getPluginMetadata: (args) => {
          seen.reads.push(args);
          return threads.getPluginMetadata ? threads.getPluginMetadata(args) : Promise.resolve(state.storedMetadata);
        },
        updatePluginMetadata: (args) => {
          seen.writes.push(args);
          if (threads.updatePluginMetadata) return threads.updatePluginMetadata(args);
          state.storedMetadata = { ...state.storedMetadata, ...args.set };
          return Promise.resolve(state.storedMetadata);
        },
      },
    },
    realtime: { publish: (channel, payload) => seen.published.push({ channel, payload }) },
    log: { info: () => {}, warn: (message) => seen.warnings.push(message) },
  });
  return { ...registered, seen, state };
}

async function instructions(models, { provider = "claude-code", model = PARENTS[provider], off = [], metadata = {} } = {}) {
  const { configure } = await load({ models, off });
  return configure({ provider: { id: provider, model, capabilities: {} }, pluginMetadata: metadata }).instructions;
}

const dispatch = (bb, text) => bb["message.dispatch"]({ thread: { id: "thr_1" }, input: { text, blocks: [] } });

const PROCEED = { action: "proceed" };

const roleLines = (text) => text.slice(text.indexOf("Role models (provider / model @effort):\n")).split("\n").slice(1);

const TS_LINE = "Before you read or edit a file matching `**/*.ts` or `**/*.tsx`, load the typescript-best-practices skill.";

const RULES = "## pstack delegation rules\n\n";

const ON = { potetoMode: "on" };

const NOTES = {
  "claude-code":
    "poteto-mode is on unless the user opts out. Per request, put its size, playbook steps, gates and reply rules in TaskCreate; reread it when unsure. Skip only where allowed. Deslop and no-comments once per PR. A brief narrows scope, never gates. Only large-slice sub-coordinators get /poteto-mode. If the playbook opens a PR, open it. Report progress freely; claim done only when every step is.",
  codex:
    "poteto-mode is on unless the user opts out. Per request, put its size, playbook steps, gates and reply rules in $BB_THREAD_STORAGE/checklist.md; reread if unsure. Skip only if allowed. Deslop and no-comments once per PR. Briefs narrow scope, never gates. Only large-slice sub-coordinators get $poteto-mode. Open a PR if the playbook does. Report progress freely; claim done only when every step is.",
};

const FALLBACK_NOTE =
  "poteto-mode is on unless the user opts out. Per request, put its size, playbook steps, gates and reply rules in your task list; reread it when unsure. Skip only where allowed. Deslop and no-comments once per PR. A brief narrows scope, never gates. Only large-slice sub-coordinators get /poteto-mode. If the playbook opens a PR, open it. Report progress freely; claim done only when every step is.";

const OWNER_MODELS = `feature, refactoring: claude-code / claude-opus-5-5 @xhigh
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

const TS_SKILL = [["typescript-best-practices", ["**/*.ts", "**/*.tsx"]]];

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
    for (const [metadata, lead] of [[{}, RULES], [ON, `${NOTES[provider]}\n\n${RULES}`]]) {
      const text = await instructions(models, { provider, metadata });
      assert.ok(text.startsWith(lead), provider);
      assert.ok(text.length <= 4096, `${provider}: ${text.length} characters`);
      assert.equal(text.includes("claude-fable-5-1 @xhigh, claude-code"), false);
      assert.match(text, new RegExp(`Run bb plugin config pstack --json\\. .* inherit-parent means ${provider} / ${PARENTS[provider]}\\.$`));
      assert.ok(text.includes(TS_LINE), provider);
    }
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
      "most are user-invoked only, so not in your skill list. Read one at ../<name>/SKILL.md from the naming skill's base directory, an unprefixed principle (**prove-it-works** principle skill) at ../principle-<name>/SKILL.md. pstack writes /<name>: say and run $<name>, and ask users typing /<name> for $<name>.\n\n"
    )
  );
  assert.ok(claude.includes("most are user-invoked only, so not in your skill list. Read one at"));
  assert.ok(claude.includes("at ../principle-<name>/SKILL.md.\n\n"));
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

  const roomy = delegationRules("codex", "gpt-6-astra", "", many, "");
  assert.ok(roomy.length <= 4096, `${roomy.length} characters`);
  assert.equal(roomy.includes("path-skill-0"), false);
  assert.match(roomy, /load each pstack skill whose SKILL\.md `paths` globs match it\.\n\nRole models \(provider \/ model @effort\):\n/);

  const tight = delegationRules("codex", "gpt-6-astra", long, many, "");
  assert.ok(tight.length <= 4096, `${tight.length} characters`);
  assert.match(tight, /load each pstack skill whose SKILL\.md `paths` globs match it\.\n\nThe role models are too long to inline here\. Run bb plugin config pstack --json\./);

  const note = "n".repeat(400);
  const noted = delegationRules("codex", "gpt-6-astra", long, many, note);
  assert.ok(noted.length <= 4096, `${noted.length} characters`);
  assert.ok(noted.startsWith(`${note}\n\n${RULES}`));
  assert.match(noted, /load each pstack skill whose SKILL\.md `paths` globs match it\.\n\nThe role models are too long to inline here\. Run bb plugin config pstack --json\./);

  const few = delegationRules("codex", "gpt-6-astra", long, many.slice(0, 1), "");
  assert.ok(few.includes("load the path-skill-0 skill.\n\nThe role models are too long"), few.slice(-600));

  const claude = delegationRules("claude-code", "claude-opus-5-5", "", many, "");
  assert.ok(claude.length <= 4096, `${claude.length} characters`);
  assert.match(claude, /load each pstack skill whose SKILL\.md `paths` globs match it\.\n\nRole models \(provider \/ model @effort\):\n/);
});

test("with poteto-mode on, each provider's instructions open with its standing note", async () => {
  for (const [provider, note] of Object.entries(NOTES)) {
    assert.ok((await instructions("", { provider, metadata: ON })).startsWith(`${note}\n\n${RULES}`), provider);
  }
  assert.ok((await instructions("", { provider: "pi", model: "pi-1", metadata: ON })).startsWith(`${FALLBACK_NOTE}\n\n${RULES}`));
});

test("no note when the mode is off, never enabled, malformed, or the poteto-mode skill is switched off", async () => {
  assert.ok((await instructions("", { metadata: ON })).startsWith(NOTES["claude-code"]));
  for (const metadata of [{ potetoMode: "off" }, {}, { potetoMode: "yes" }, { potetoMode: true }, { mode: "on" }]) {
    const text = await instructions("", { metadata });
    assert.ok(text.startsWith(RULES), JSON.stringify(metadata));
    assert.equal(text.includes("poteto-mode is on"), false, JSON.stringify(metadata));
  }
  assert.ok((await instructions("", { metadata: ON, off: ["poteto-mode"] })).startsWith(RULES));
});

test("with the real note, the owner's setting keeps the role models and the paths line inline", async () => {
  for (const provider of Object.keys(PARENTS)) {
    const text = await instructions(OWNER_MODELS, { provider, metadata: ON });
    assert.ok(text.startsWith(`${NOTES[provider]}\n\n${RULES}`), provider);
    assert.ok(text.length <= 4096, `${provider}: ${text.length} characters`);
    assert.match(text, /^interrogate reviewers: .+ @xhigh$/m);
    assert.ok(text.includes(`${TS_LINE}\n\nRole models`), provider);
  }
});

test("a 400-character note fits with the owner's setting, the role models and the paths line", () => {
  const note = "n".repeat(400);
  for (const [provider, model] of Object.entries(PARENTS)) {
    const text = delegationRules(provider, model, OWNER_MODELS, TS_SKILL, note);
    assert.ok(text.startsWith(`${note}\n\n${RULES}`), provider);
    assert.ok(text.length <= 4096, `${provider}: ${text.length} characters`);
    assert.match(text, /^interrogate reviewers: .+ @xhigh$/m);
    assert.ok(text.includes(`${TS_LINE}\n\nRole models`), provider);
  }
});

test("a mapping that fits alone but not beside the note gives way to where to read it", async () => {
  const swarm = Array.from({ length: 8 }, () => "claude-code / claude-opus-5-5 @high").join(", ");
  for (const provider of Object.keys(PARENTS)) {
    const alone = await instructions(`swarm workers: ${swarm}`, { provider });
    assert.ok(alone.length <= 4096, `${provider}: ${alone.length} characters`);
    assert.ok(alone.includes(`swarm workers: ${swarm}\n`), provider);

    const noted = await instructions(`swarm workers: ${swarm}`, { provider, metadata: ON });
    assert.ok(noted.startsWith(`${NOTES[provider]}\n\n${RULES}`), provider);
    assert.ok(noted.length <= 4096, `${provider}: ${noted.length} characters`);
    assert.equal(noted.includes(`swarm workers: ${swarm}`), false, provider);
    assert.match(noted, /The role models are too long to inline here\./);
  }
});

test("every provider's note stays within the 400 characters the rules leave for it", async () => {
  for (const provider of [...Object.keys(POTETO_NOTES), "pi"]) {
    const text = await instructions("", { provider, model: "any-model", metadata: ON });
    const note = text.slice(0, text.indexOf(`\n\n${RULES}`));
    assert.ok(note.startsWith("poteto-mode is on"), provider);
    assert.ok(note.length <= 400, `${provider}: ${note.length} characters`);
  }
});

test("a /poteto-mode line turns the mode on once, tells open chips, and proceeds", async () => {
  const bb = await load();
  assert.deepEqual(await dispatch(bb, "/poteto-mode\nfix the flaky test"), PROCEED);
  assert.deepEqual(bb.state.storedMetadata, { potetoMode: "on" });
  const { signal, ...write } = bb.seen.writes[0];
  assert.deepEqual(write, { threadId: "thr_1", set: { potetoMode: "on" } });
  assert.ok(signal instanceof AbortSignal);
  assert.deepEqual(bb.seen.published, [{ channel: "poteto-mode", payload: { threadId: "thr_1" } }]);

  assert.deepEqual(await dispatch(bb, "/poteto-mode\nfix the flaky test"), PROCEED);
  assert.equal(bb.seen.reads.length, 2);
  assert.equal(bb.seen.writes.length, 1);
  assert.equal(bb.seen.published.length, 1);
});

test("a $poteto-mode line on any line of the message turns the mode on", async () => {
  const bb = await load();
  assert.deepEqual(await dispatch(bb, "fix the flaky test\n$poteto-mode"), PROCEED);
  assert.deepEqual(bb.state.storedMetadata, { potetoMode: "on" });
  assert.deepEqual(bb.seen.published, [{ channel: "poteto-mode", payload: { threadId: "thr_1" } }]);
});

test("a thread already on gets no write, and one that opted out is turned back on", async () => {
  const on = await load({ storedMetadata: { potetoMode: "on" } });
  assert.deepEqual(await dispatch(on, "/poteto-mode"), PROCEED);
  assert.equal(on.seen.reads.length, 1);
  assert.deepEqual(on.seen.writes, []);
  assert.deepEqual(on.seen.published, []);

  const off = await load({ storedMetadata: { potetoMode: "off" } });
  assert.deepEqual(await dispatch(off, "/poteto-mode"), PROCEED);
  assert.deepEqual(off.state.storedMetadata, { potetoMode: "on" });
  assert.deepEqual(off.seen.published, [{ channel: "poteto-mode", payload: { threadId: "thr_1" } }]);
});

test("no invocation, a mid-line mention, a longer name, or a switched-off skill makes no SDK call", async () => {
  const quiet = { reads: [], writes: [], published: [], warnings: [] };
  for (const text of ["fix the flaky test", "try /poteto-mode later", "/poteto-modes", "$poteto-mode-lite"]) {
    const bb = await load();
    assert.deepEqual(await dispatch(bb, text), PROCEED);
    assert.deepEqual(bb.seen, quiet, text);
  }
  for (const off of [["skills"], ["poteto-mode"]]) {
    const bb = await load({ off });
    assert.deepEqual(await dispatch(bb, "/poteto-mode"), PROCEED);
    assert.deepEqual(bb.seen, quiet, off[0]);
  }
  const control = await load();
  await dispatch(control, "/poteto-mode");
  assert.equal(control.seen.reads.length, 1);
});

test("a failing metadata read logs one warning and still proceeds", async () => {
  const bb = await load({
    threads: {
      getPluginMetadata: () => {
        throw new Error("metadata store down");
      },
    },
  });
  assert.deepEqual(await dispatch(bb, "/poteto-mode"), PROCEED);
  assert.deepEqual(bb.seen.warnings, ["poteto-mode: could not turn the mode on for thread thr_1: metadata store down"]);
  assert.deepEqual(bb.seen.writes, []);
  assert.deepEqual(bb.seen.published, []);
});

test("one 3-second budget covers a slow read and a hung write, and the message still proceeds", async () => {
  const bb = await load({
    threads: {
      getPluginMetadata: () => new Promise((resolve) => setTimeout(() => resolve({}), 1500)),
      updatePluginMetadata: ({ signal }) => new Promise((_, reject) => signal.addEventListener("abort", () => reject(signal.reason))),
    },
  });
  const started = performance.now();
  assert.deepEqual(await dispatch(bb, "/poteto-mode"), PROCEED);
  const elapsed = performance.now() - started;
  assert.ok(elapsed >= 2900 && elapsed < 3500, `${Math.round(elapsed)} ms`);
  assert.deepEqual(bb.seen.warnings, ["poteto-mode: could not turn the mode on for thread thr_1: The operation was aborted due to timeout"]);
  assert.deepEqual(bb.seen.published, []);
});
