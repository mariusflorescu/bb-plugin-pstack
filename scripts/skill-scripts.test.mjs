// Runs every shell test that ships inside a skill (skills/*/scripts/<name>.test.sh
// against its skills/*/scripts/<name>.sh), so `node --test scripts/` covers them too.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readdirSync, existsSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const SKILLS = join(ROOT, "skills");

const suites = readdirSync(SKILLS)
  .filter((skill) => !skill.startsWith(".") && existsSync(join(SKILLS, skill, "scripts")))
  .flatMap((skill) =>
    readdirSync(join(SKILLS, skill, "scripts"))
      .filter((file) => file.endsWith(".test.sh"))
      .map((file) => ({
        skill,
        suite: join(SKILLS, skill, "scripts", file),
        script: join(SKILLS, skill, "scripts", file.replace(/\.test\.sh$/, ".sh")),
      }))
  );

test("every skill shell test has the script it tests", () => {
  assert.ok(suites.length > 0, "found skill shell tests");
  for (const { suite, script } of suites) assert.ok(existsSync(script), `${suite} tests a missing ${script}`);
});

for (const { skill, suite, script } of suites) {
  test(`${skill}: ${suite.slice(SKILLS.length + 1)}`, () => {
    const run = spawnSync("bash", [suite, script], { cwd: ROOT, encoding: "utf8", timeout: 600000 });
    assert.equal(run.status, 0, `exit ${run.status}\n${(run.stdout + run.stderr).split("\n").filter((line) => /FAIL|error/i.test(line)).join("\n")}`);
  });
}
