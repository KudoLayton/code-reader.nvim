vim.opt.runtimepath:append(vim.fn.getcwd())

package.path = table.concat({
  "lua/?.lua",
  "lua/?/init.lua",
  package.path,
}, ";")

local diff = require("code_reader.diff")
local render = require("code_reader.diff_render")

local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)), 2)
  end
end

local function ok(value, label)
  if not value then
    error(label, 2)
  end
end

local sample = [[
diff --git a/src/sample.lua b/src/sample.lua
index 1111111..2222222 100644
--- a/src/sample.lua
+++ b/src/sample.lua
@@ -1,9 +1,9 @@
 local steps = {
-  "parse",
   "validate",
+  "parse",
   "render",
 }
 
-local obsolete = true
+table.insert(events, "created")
-local status = status_line(200)
+local status = status_line(201)
 
]]

local parsed = diff.parse(sample)
local hunk = parsed.files[1].hunks[1]
local model = render.render_hunk(hunk)

eq(model.summary.modified, 1, "modified pair count")
eq(model.summary.moved, 1, "moved pair count")
eq(model.summary.added, 1, "pure addition count")
eq(model.summary.deleted, 1, "pure deletion count")

local moved_before = nil
local moved_after = nil
local modified_before = nil
local modified_after = nil
local pure_delete = nil
local pure_add = nil

for _, row in ipairs(model.rows) do
  if row.before and row.before.text == '  "parse",' then
    moved_before = row.before
  end
  if row.after and row.after.text == '  "parse",' then
    moved_after = row.after
  end
  if row.before and row.before.text == "local status = status_line(200)" then
    modified_before = row.before
  end
  if row.after and row.after.text == "local status = status_line(201)" then
    modified_after = row.after
  end
  if row.before and row.before.text == "local obsolete = true" then
    pure_delete = row.before
  end
  if row.after and row.after.text == 'table.insert(events, "created")' then
    pure_add = row.after
  end
end

eq(moved_before and moved_before.kind, "moved", "moved before kind")
eq(moved_after and moved_after.kind, "moved", "moved after kind")
eq(moved_before and moved_before.marker, ">", "moved before marker")
eq(moved_after and moved_after.marker, ">", "moved after marker")

eq(modified_before and modified_before.kind, "modified", "modified before kind")
eq(modified_after and modified_after.kind, "modified", "modified after kind")
eq(modified_before and modified_before.marker, "~", "modified before marker")
eq(modified_after and modified_after.marker, "~", "modified after marker")
ok(#(modified_before and modified_before.spans or {}) > 0, "modified before spans")
ok(#(modified_after and modified_after.spans or {}) > 0, "modified after spans")

eq(pure_delete and pure_delete.kind, "deleted", "pure delete kind")
eq(pure_delete and pure_delete.marker, "-", "pure delete marker")
eq(pure_add and pure_add.kind, "added", "pure add kind")
eq(pure_add and pure_add.marker, "+", "pure add marker")

local before_text = table.concat(model.before_lines, "\n")
local after_text = table.concat(model.after_lines, "\n")
ok(before_text:find("%s*>%s+\"parse\",") ~= nil, "before gutter moved marker")
ok(before_text:find("%s*~%s+local status = status_line%(200%)") ~= nil, "before gutter modified marker")
ok(after_text:find('%s*%+%s+table.insert%(events, "created"%)') ~= nil, "after gutter add marker")

local indentation_sample = [[
diff --git a/src/indent.lua b/src/indent.lua
index 1111111..2222222 100644
--- a/src/indent.lua
+++ b/src/indent.lua
@@ -1,4 +1,4 @@
 local steps = {
-"parse",
   "validate",
+  "parse",
 }
]]

local indentation_hunk = diff.parse(indentation_sample).files[1].hunks[1]
local indentation_model = render.render_hunk(indentation_hunk)
eq(indentation_model.summary.moved, 1, "indentation moved count")

local unrelated_sample = [[
diff --git a/src/unrelated.lua b/src/unrelated.lua
index 1111111..2222222 100644
--- a/src/unrelated.lua
+++ b/src/unrelated.lua
@@ -1,3 +1,3 @@
 local M = {}
-return handle(legacy)
+local created = true
 end
]]

local unrelated_hunk = diff.parse(unrelated_sample).files[1].hunks[1]
local unrelated_model = render.render_hunk(unrelated_hunk)
eq(unrelated_model.summary.modified, 0, "unrelated modified count")
eq(unrelated_model.summary.deleted, 1, "unrelated deleted count")
eq(unrelated_model.summary.added, 1, "unrelated added count")

local range = render.resolve_hunk_range(hunk, "new", {
  start_bound = { mode = "relative", value = -1 },
  end_bound = { mode = "relative", value = 1 },
})
eq(range.start_line, 1, "relative range start")
eq(range.end_line, 10, "relative range end")

local focused_model = render.render_file(
  parsed.files[1],
  {
    "header",
    "local steps = {",
    '  "validate",',
    '  "render",',
    "}",
    "",
    "local obsolete = true",
    "local status = status_line(200)",
    "",
    "footer",
  },
  {
    "header",
    "local steps = {",
    '  "validate",',
    '  "parse",',
    '  "render",',
    "}",
    "",
    'table.insert(events, "created")',
    "local status = status_line(201)",
    "",
    "footer",
  },
  hunk,
  { side = "new", padding = 2 }
)
local focused_before = table.concat(focused_model.before_lines, "\n")
local focused_after = table.concat(focused_model.after_lines, "\n")
eq(#focused_model.rows, 12, "focused full file row count")
eq(focused_model.focus_start, 1, "range focus start")
eq(focused_model.focus_end, 12, "range focus end")
ok(focused_before:find("local steps = {", 1, true) ~= nil, "focused view keeps full file")
ok(focused_after:find("footer", 1, true) ~= nil, "focused view keeps trailing file content")
ok(focused_after:find('table.insert(events, "created")', 1, true) ~= nil, "focused view includes hunk change")

print("diff_render_spec: ok")
