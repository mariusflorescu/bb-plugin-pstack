// The SKILL.md frontmatter fields the scripts act on, parsed with a real YAML
// parser so every form Claude Code accepts reads the same here. Shared so the
// generator and the checker cannot disagree.
import { parse } from "yaml";

// The parsed frontmatter, or {} when a file has none. Throws on invalid YAML.
export function frontmatter(text) {
  const block = text.match(/^---\n([\s\S]*?)\n---/)?.[1];
  if (block === undefined) return {};
  const data = parse(block);
  return data !== null && typeof data === "object" && !Array.isArray(data) ? data : {};
}

// The description on one line; a block scalar's line breaks become spaces.
export const description = (fm) => (typeof fm.description === "string" ? fm.description.replace(/\s+/g, " ").trim() : "");

// Claude Code hides a skill from the model only for the boolean true.
export const isUserOnly = (fm) => fm["disable-model-invocation"] === true;

// Split a comma-separated string, keeping a brace glob such as `*.{ts,tsx}` whole.
function splitCommas(text) {
  const parts = [""];
  let depth = 0;
  for (const ch of text) {
    if (ch === "," && depth === 0) {
      parts.push("");
      continue;
    }
    if (ch === "{") depth++;
    else if (ch === "}") depth--;
    parts[parts.length - 1] += ch;
  }
  return parts;
}

// `paths` as Claude Code reads it: a YAML list or a comma-separated string.
export function paths(fm) {
  const value = fm.paths;
  const items = Array.isArray(value) ? value : typeof value === "string" ? splitCommas(value) : [];
  return items.filter((item) => typeof item === "string").map((item) => item.trim()).filter(Boolean);
}
