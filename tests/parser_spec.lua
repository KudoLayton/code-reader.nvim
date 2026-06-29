package.path = table.concat({
  "lua/?.lua",
  "lua/?/init.lua",
  package.path,
}, ";")

local parser = require("code_reader.parser")

local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)), 2)
  end
end

local sample = [[
---
type: code-reader
version: 1
---

<!-- code-reader: front-page -->
# Code Reader Overview

This walkthrough explains the request flow.

---
# 1. Request lifecycle

Source: `src/server.lua#L10-L30`

The top-level flow.

---
## 1.1. Parse request

Source: [parser](src/parser.lua#L5-L12)

Nested call-stack detail.

---
# 2. Render result

No explicit source in this step.
]]

local doc = parser.parse(sample, { path = ".code_reader/flow.md" })

eq(doc.frontmatter.type, "code-reader", "frontmatter type")
eq(doc.frontmatter.version, "1", "frontmatter version")
eq(#doc.steps, 4, "step count")
eq(doc.front_page_index, 1, "front page index")

eq(doc.steps[1].kind, "front_page", "front page kind")
eq(doc.steps[1].id, "front", "front page id")
eq(doc.steps[1].title, "Code Reader Overview", "front page title")
eq(doc.steps[1].depth, 1, "front page depth")
eq(doc.steps[1].content:find("code-reader: front-page", 1, true), nil, "front page marker removed from content")
eq(doc.steps[1].body:find("code-reader: front-page", 1, true), nil, "front page marker removed from body")

eq(doc.steps[2].id, "1", "first step id")
eq(doc.steps[2].title, "Request lifecycle", "first step title")
eq(doc.steps[2].depth, 1, "first step depth")
eq(doc.steps[2].sources[1].path, "src/server.lua", "first source path")
eq(doc.steps[2].sources[1].start_line, 10, "first source start")
eq(doc.steps[2].sources[1].end_line, 30, "first source end")

eq(doc.steps[3].id, "1.1", "nested step id")
eq(doc.steps[3].title, "Parse request", "nested step title")
eq(doc.steps[3].depth, 2, "nested step depth")
eq(doc.step_by_id["1.1"], 3, "nested step lookup")
eq(doc.steps[3].sources[1].path, "src/parser.lua", "nested source path")
eq(doc.steps[3].sources[1].start_line, 5, "nested source start")
eq(doc.steps[3].sources[1].end_line, 12, "nested source end")

eq(doc.steps[4].id, "2", "third step id")
eq(doc.steps[4].title, "Render result", "third step title")
eq(#doc.steps[4].sources, 0, "third step source count")

local legacy_sample = [[
---
type: code-reader
version: 1
---

# 1. Legacy step

No explicit source in this step.
]]

local legacy_doc = parser.parse(legacy_sample, { path = ".code_reader/legacy.md" })
eq(legacy_doc.front_page_index, nil, "legacy front page index")
eq(legacy_doc.steps[1].kind, "step", "legacy step kind")
eq(legacy_doc.steps[1].id, "1", "legacy step id")

local diff_sample = [[
---
type: code-reader-diff
version: 1
diff: ./changes.diff
---

<!-- code-reader: front-page -->
# Diff Overview

Explain the change.

---
# 1. Toggle flag

Diff: `src/app.lua#H2`
]]

local diff_doc = parser.parse(diff_sample, { path = ".code_reader/diffs/changes.md" })
eq(diff_doc.frontmatter.type, "code-reader-diff", "diff frontmatter type")
eq(diff_doc.frontmatter.diff, "./changes.diff", "diff frontmatter path")
eq(diff_doc.steps[2].diff_refs[1].path, "src/app.lua", "diff ref path")
eq(diff_doc.steps[2].diff_refs[1].hunk_id, "H2", "diff ref hunk")

print("parser_spec: ok")
