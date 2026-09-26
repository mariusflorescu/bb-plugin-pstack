// Rerunnable check for scripts/frontmatter.mjs: node --test scripts/
import { test } from "node:test";
import assert from "node:assert/strict";
import { description, isUserOnly, paths } from "./frontmatter.mjs";

test("disable-model-invocation is true only as an unquoted YAML boolean, comment or not", () => {
  assert.equal(isUserOnly("name: a\ndisable-model-invocation: true"), true);
  assert.equal(isUserOnly("disable-model-invocation: true # explicit invocation only"), true);
  assert.equal(isUserOnly("disable-model-invocation:   True  "), true);
  assert.equal(isUserOnly("disable-model-invocation: false # not true"), false);
  assert.equal(isUserOnly('disable-model-invocation: "true"'), false);
  assert.equal(isUserOnly("name: a"), false);
});

test("paths keeps commas inside quotes and brace globs, and reads every list form", () => {
  assert.deepEqual(paths('paths: ["**/*.ts", "**/*.tsx"]'), ["**/*.ts", "**/*.tsx"]);
  assert.deepEqual(paths('paths: ["**/*.{ts,tsx}", \'src/a, b/**\'] # comment'), ["**/*.{ts,tsx}", "src/a, b/**"]);
  assert.deepEqual(paths('paths: [\n  "**/*.ts",\n  "**/*.{md,mdx}",\n]\nname: a'), ["**/*.ts", "**/*.{md,mdx}"]);
  assert.deepEqual(paths("paths:\n  - \"**/migrations/**\" # sql\n  - '*.sql'\nname: a"), ["**/migrations/**", "*.sql"]);
  assert.deepEqual(paths("paths: src/**/*.{ts,tsx}, *.toml"), ["src/**/*.{ts,tsx}", "*.toml"]);
  assert.deepEqual(paths('paths: "lib/**, *.rs"'), ["lib/**", "*.rs"]);
  assert.deepEqual(paths("name: a"), []);
});

test("description reads plain, quoted and folded values", () => {
  assert.equal(description("description: Plain text."), "Plain text.");
  assert.equal(description('description: "Does \\"a\\"."'), 'Does "a".');
  assert.equal(description("description: >-\n  Folded over\n  two lines.\nname: a"), "Folded over two lines.");
});
