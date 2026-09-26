// Rerunnable check for scripts/frontmatter.mjs: node --test scripts/
import { test } from "node:test";
import assert from "node:assert/strict";
import { frontmatter, description, isUserOnly, paths } from "./frontmatter.mjs";

const fm = (...lines) => frontmatter(["---", ...lines, "---", "", "# Body"].join("\n"));

test("disable-model-invocation is true only as a YAML boolean, comment or not", () => {
  assert.equal(isUserOnly(fm("name: a", "disable-model-invocation: true")), true);
  assert.equal(isUserOnly(fm("disable-model-invocation: true # explicit invocation only")), true);
  assert.equal(isUserOnly(fm("disable-model-invocation: True")), true);
  assert.equal(isUserOnly(fm("disable-model-invocation: false # not true")), false);
  assert.equal(isUserOnly(fm('disable-model-invocation: "true"')), false);
  assert.equal(isUserOnly(fm("name: a")), false);
});

test("paths reads every YAML list form, with comments, and keeps brace globs whole", () => {
  assert.deepEqual(paths(fm('paths: ["**/*.ts", "**/*.tsx"]')), ["**/*.ts", "**/*.tsx"]);
  assert.deepEqual(paths(fm("paths: [\"**/*.{ts,tsx}\", 'src/a, b/**'] # comment")), ["**/*.{ts,tsx}", "src/a, b/**"]);
  assert.deepEqual(paths(fm("paths: [", '  "**/*.ts", # TypeScript', '  "**/*.tsx"', "]", "name: a")), ["**/*.ts", "**/*.tsx"]);
  assert.deepEqual(paths(fm("paths: [ # globs", '  "**/*.md",', "]")), ["**/*.md"]);
  assert.deepEqual(paths(fm("paths:", '  - "**/migrations/**" # sql', "  - '*.sql'", "name: a")), ["**/migrations/**", "*.sql"]);
  assert.deepEqual(paths(fm("paths:", '- "**/*.py"', "- '*.pyi'", "name: a")), ["**/*.py", "*.pyi"]);
  assert.deepEqual(paths(fm("paths: src/**/*.{ts,tsx}, *.toml")), ["src/**/*.{ts,tsx}", "*.toml"]);
  assert.deepEqual(paths(fm('paths: "lib/**, *.rs"')), ["lib/**", "*.rs"]);
  assert.deepEqual(paths(fm("name: a")), []);
});

test("description reads plain, quoted and block values on one line", () => {
  assert.equal(description(fm("description: Plain text.")), "Plain text.");
  assert.equal(description(fm('description: "Does \\"a\\"."')), 'Does "a".');
  assert.equal(description(fm("description: >-", "  Folded over", "  two lines.", "name: a")), "Folded over two lines.");
  assert.equal(description(fm("description: |", "  Kept", "  lines.")), "Kept lines.");
});

test("a file without frontmatter reads as empty, and invalid YAML throws", () => {
  assert.deepEqual(frontmatter("# Just a body\n"), {});
  assert.throws(() => fm("description: a: b: c", "paths: [unclosed"));
});
