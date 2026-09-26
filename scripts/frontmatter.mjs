// The SKILL.md frontmatter fields the scripts act on, read the way a YAML
// parser reads them: quotes, flow lists over several lines, and trailing
// comments. Shared so the generator and the checker cannot disagree.

// The frontmatter block between the opening and closing `---`, or "".
export function frontmatterBlock(text) {
  return text.match(/^---\n([\s\S]*?)\n---/)?.[1] ?? "";
}

function parseDoubleQuoted(raw) {
  try {
    return JSON.parse(raw);
  } catch {
    return raw.slice(1, -1).replace(/\\"/g, '"');
  }
}

export const unquote = (raw) => (raw.startsWith('"') ? parseDoubleQuoted(raw) : raw.replace(/^'(.*)'$/, "$1").replace(/''/g, "'"));

// Split on `separator` outside quotes and brackets, and stop at a ` #` comment
// outside quotes.
function splitOutside(text, separator) {
  const parts = [];
  let current = "";
  let quote = null;
  let depth = 0;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quote) {
      current += ch;
      if (ch === quote) quote = null;
      continue;
    }
    if (ch === '"' || ch === "'") quote = ch;
    else if (ch === "#" && (i === 0 || /\s/.test(text[i - 1]))) break;
    else if ("{[".includes(ch)) depth++;
    else if ("}]".includes(ch)) depth--;
    else if (ch === separator && depth === 0) {
      parts.push(current.trim());
      current = "";
      continue;
    }
    current += ch;
  }
  parts.push(current.trim());
  return parts;
}

const stripComment = (raw) => splitOutside(raw, null)[0];

// The raw text after `key:` on its line, and the lines below it.
function field(frontmatter, key) {
  const lines = frontmatter.split("\n");
  const at = lines.findIndex((line) => line.startsWith(`${key}:`));
  return at === -1 ? null : { raw: lines[at].slice(key.length + 1), below: lines.slice(at + 1) };
}

// A block scalar (`>-`, `|` and the like) keeps its text on the indented lines
// below the key. Folding every line break to a space is enough for a summary.
export function description(frontmatter) {
  const found = field(frontmatter, "description");
  if (!found) return "";
  const raw = found.raw.trim();
  if (/^[>|][+-]?$/.test(raw)) {
    const body = [];
    for (const line of found.below) {
      if (line.trim() !== "" && !/^\s/.test(line)) break;
      body.push(line.trim());
    }
    return body.join(" ").replace(/\s+/g, " ").trim();
  }
  return unquote(raw);
}

// True only for an unquoted YAML boolean true, as Claude Code reads it.
export function isUserOnly(frontmatter) {
  const found = field(frontmatter, "disable-model-invocation");
  return found !== null && /^(true|True|TRUE)$/.test(stripComment(found.raw));
}

// `paths` as Claude Code reads it: a YAML list (flow, possibly over several
// lines, or block) or a comma-separated string. A comma inside quotes or a
// brace glob such as `**/*.{ts,tsx}` stays inside its pattern.
export function paths(frontmatter) {
  const found = field(frontmatter, "paths");
  if (!found) return [];
  const raw = stripComment(found.raw);
  let items;
  if (raw === "") {
    items = [];
    for (const line of found.below) {
      const item = line.match(/^\s+-\s+(.+)$/);
      if (!item) break;
      items.push(stripComment(item[1]));
    }
  } else if (raw.startsWith("[")) {
    let flow = found.raw.trim();
    for (const line of found.below) {
      if (splitOutside(flow, null)[0].endsWith("]")) break;
      flow += " " + line.trim();
    }
    items = splitOutside(stripComment(flow).replace(/^\[/, "").replace(/\]$/, ""), ",");
  } else {
    items = /^["']/.test(raw) ? splitOutside(unquote(raw), ",") : splitOutside(raw, ",");
  }
  return items.map((item) => unquote(item.trim())).filter(Boolean);
}
