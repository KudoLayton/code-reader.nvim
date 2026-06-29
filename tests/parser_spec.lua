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
eq(#doc.steps, 3, "step count")

eq(doc.steps[1].id, "1", "first step id")
eq(doc.steps[1].title, "Request lifecycle", "first step title")
eq(doc.steps[1].depth, 1, "first step depth")
eq(doc.steps[1].sources[1].path, "src/server.lua", "first source path")
eq(doc.steps[1].sources[1].start_line, 10, "first source start")
eq(doc.steps[1].sources[1].end_line, 30, "first source end")

eq(doc.steps[2].id, "1.1", "nested step id")
eq(doc.steps[2].title, "Parse request", "nested step title")
eq(doc.steps[2].depth, 2, "nested step depth")
eq(doc.step_by_id["1.1"], 2, "nested step lookup")
eq(doc.steps[2].sources[1].path, "src/parser.lua", "nested source path")
eq(doc.steps[2].sources[1].start_line, 5, "nested source start")
eq(doc.steps[2].sources[1].end_line, 12, "nested source end")

eq(doc.steps[3].id, "2", "third step id")
eq(doc.steps[3].title, "Render result", "third step title")
eq(#doc.steps[3].sources, 0, "third step source count")

print("parser_spec: ok")
