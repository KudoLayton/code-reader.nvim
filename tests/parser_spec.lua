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
Cursor: `src/server.lua#L12`

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
eq(doc.steps[2].sources[1].cursor_line, 12, "first source cursor")
eq(doc.steps[2].content:find("Source:", 1, true), nil, "source directive removed from content")
eq(doc.steps[2].content:find("Cursor:", 1, true), nil, "cursor directive removed from content")

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

Diff: `src/app.lua#H1@old:L(-1)-L22`
Diff: `src/app.lua#H1@new:padding=2`
Diff: `src/app.lua#H1@b:L-1-L22`
]]

local diff_doc = parser.parse(diff_sample, { path = ".code_reader/diffs/changes.md" })
eq(diff_doc.frontmatter.type, "code-reader-diff", "diff frontmatter type")
eq(diff_doc.frontmatter.diff, "./changes.diff", "diff frontmatter path")
eq(diff_doc.steps[2].diff_refs[1].path, "src/app.lua", "diff ref path")
eq(diff_doc.steps[2].diff_refs[1].hunk_id, "H2", "diff ref hunk")
eq(diff_doc.steps[2].diff_refs[2].side, "old", "diff ref old side")
eq(diff_doc.steps[2].diff_refs[2].start_bound.mode, "relative", "diff ref relative start")
eq(diff_doc.steps[2].diff_refs[2].start_bound.value, -1, "diff ref relative start value")
eq(diff_doc.steps[2].diff_refs[2].end_bound.mode, "absolute", "diff ref absolute end")
eq(diff_doc.steps[2].diff_refs[2].end_bound.value, 22, "diff ref absolute end value")
eq(diff_doc.steps[2].diff_refs[3].side, "new", "diff ref padding side")
eq(diff_doc.steps[2].diff_refs[3].padding, 2, "diff ref padding")
eq(diff_doc.steps[2].diff_refs[4].side, "new", "diff ref alias side")
eq(diff_doc.steps[2].diff_refs[4].start_bound.mode, "relative", "diff ref shorthand relative start")

local v2_sample = [[
---
type: code-reader
version: 2
feature: request-flow
---

# Request flow overview

```code-reader
kind: overview
id: request-flow
question: How does a request become a response?
state:
  status: not_applicable
  reason: The overview does not change runtime state.
responsibility:
  status: applicable
  items:
    - owner: app.handle
      action: Coordinate the request lifecycle
      owns:
        - lifecycle order
```

The stages below explain the lifecycle.

---
# 1. Validate request

```code-reader
kind: stage
id: validate-request
question: How is a decoded request accepted?
trigger: app.handle calls validate_request
state:
  status: applicable
  changes:
    - subject: request
      owner: request.validate_request
      before: decoded
      cause: validation succeeds
      after: validated
      invariant: invalid requests do not dispatch
responsibility:
  status: applicable
  items:
    - owner: request.validate_request
      action: Reject unsupported methods
      owns:
        - method policy
failure:
  status: applicable
  outcomes:
    - cause: unsupported method
      result: error response
evidence:
  - id: 1
    kind: source
    target: src/request.lua#L15-L25
    cursor: src/request.lua#L18
    claim: Validation decides whether dispatch may continue.
  - id: 2
    kind: sketch
    purpose: handoff-map
    target: .code_reader/assets/request-validation.svg
    editable_target: .code_reader/assets/request-validation.excalidraw
    claim: Validation transfers a request across the dispatch boundary.
    text_model:
      claim: Validated requests cross the boundary.
      nodes:
        - id: decoded
          label: Decoded request
          owner: app.handle
          state: decoded
        - id: validated
          label: Validated request
          owner: dispatcher
          state: validated
      edges:
        - from: decoded
          to: validated
          label: validate
```

Validation establishes the dispatch invariant [1](code-reader://evidence/1).
The ownership handoff is summarized visually [2](code-reader://evidence/2).
]]

local v2_doc = parser.parse(v2_sample, { path = ".code_reader/v2.md" })
eq(v2_doc.frontmatter.version, "2", "v2 frontmatter version")
eq(v2_doc.version_supported, true, "v2 version supported")
eq(v2_doc.front_page_index, 1, "v2 overview is front page")
eq(v2_doc.steps[1].kind, "front_page", "v2 overview kind")
eq(v2_doc.steps[2].metadata.kind, "stage", "v2 stage metadata kind")
eq(v2_doc.steps[2].metadata.state.changes[1].after, "validated", "v2 nested state metadata")
eq(#v2_doc.steps[2].evidence, 2, "v2 evidence count")
eq(v2_doc.steps[2].evidence[1].source.path, "src/request.lua", "v2 source evidence path")
eq(v2_doc.steps[2].evidence[1].source.cursor_line, 18, "v2 source evidence cursor")
eq(v2_doc.steps[2].evidence[2].kind, "sketch", "v2 sketch evidence kind")
eq(v2_doc.steps[2].evidence[2].purpose, "handoff-map", "v2 sketch purpose")
eq(v2_doc.steps[2].evidence[2].editable_path, ".code_reader/assets/request-validation.excalidraw", "v2 sketch editable path")
eq(v2_doc.steps[2].evidence_by_id[2].text_model.nodes[2].owner, "dispatcher", "v2 sketch text model")
eq(v2_doc.steps[2].content:find("```code%-reader", 1), nil, "v2 metadata fence hidden from content")

local hierarchy_sample = [[
---
type: code-reader
version: 2
feature: hierarchy
---
# Overview
```code-reader
kind: overview
id: hierarchy
```
---
# Shared validation model
```code-reader
kind: model
id: validation-model
```
---
# Parse input
```code-reader
kind: stage
id: parse-input
parent: validation-model
```
---
# Apply policy
```code-reader
kind: stage
id: apply-policy
parent: validation-model
```
]]

local hierarchy_doc = parser.parse(hierarchy_sample, { path = ".code_reader/hierarchy.md" })
eq(hierarchy_doc.steps[3].parent_id, "validation-model", "v2 explicit parent id")
eq(#hierarchy_doc.steps[2].child_ids, 2, "v2 explicit children")
eq(hierarchy_doc.steps[2].child_ids[1], "parse-input", "first explicit child")
eq(hierarchy_doc.steps[2].child_ids[2], "apply-policy", "second explicit child")

print("parser_spec: ok")
