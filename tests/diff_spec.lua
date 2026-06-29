package.path = table.concat({
  "lua/?.lua",
  "lua/?/init.lua",
  package.path,
}, ";")

local diff = require("code_reader.diff")

local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)), 2)
  end
end

local sample = [[
diff --git a/src/app.lua b/src/app.lua
index 1111111..2222222 100644
--- a/src/app.lua
+++ b/src/app.lua
@@ -1,4 +1,5 @@
 local M = {}
-local enabled = false
+local enabled = true
+local mode = "fast"
 
 return M
@@ -8,3 +9,3 @@
 function M.name()
-  return "old"
+  return "new"
 end
]]

local parsed = diff.parse(sample)
eq(#parsed.files, 1, "file count")
eq(parsed.files[1].path, "src/app.lua", "file path")
eq(#parsed.files[1].hunks, 2, "hunk count")
eq(parsed.files[1].changed_lines, 5, "changed lines")
eq(parsed.total_changed_lines, 5, "total changed lines")

local first = parsed.files[1].hunks[1]
eq(first.old_start, 1, "first old start")
eq(first.old_end, 4, "first old end")
eq(first.new_start, 1, "first new start")
eq(first.new_end, 5, "first new end")
eq(first.changed_lines, 3, "first changed lines")

local before = {
  "local M = {}",
  "local enabled = false",
  "",
  "return M",
  "",
  "",
  "",
  "function M.name()",
  "  return \"old\"",
  "end",
}

local after = {
  "local M = {}",
  "local enabled = true",
  "local mode = \"fast\"",
  "",
  "return M",
  "",
  "",
  "",
  "function M.name()",
  "  return \"new\"",
  "end",
}

local applies = diff.analyze_file(parsed.files[1], before)
eq(applies.status, "applies", "before status")
eq(table.concat(applies.before_lines, "\n"), table.concat(before, "\n"), "before lines")
eq(table.concat(applies.after_lines, "\n"), table.concat(after, "\n"), "after lines")

local already = diff.analyze_file(parsed.files[1], after)
eq(already.status, "already-applied", "after status")
eq(table.concat(already.before_lines, "\n"), table.concat(before, "\n"), "reverse before lines")
eq(table.concat(already.after_lines, "\n"), table.concat(after, "\n"), "reverse after lines")

local partial_source = {
  "local M = {}",
  "local enabled = false",
  "",
  "return M",
  "",
  "",
  "",
  "function M.name()",
  "  return \"custom\"",
  "end",
}

local partial = diff.analyze_file(parsed.files[1], partial_source)
eq(partial.status, "partial", "partial status")

local stale = diff.analyze_file(parsed.files[1], { "unrelated" })
eq(stale.status, "stale", "stale status")

local before_side, after_side = diff.hunk_sides(first)
eq(#before_side, #after_side, "side line count")
eq(before_side[2], "local enabled = false", "deleted side")
eq(after_side[2], "", "deleted side padding")
eq(before_side[3], "", "added side padding")
eq(after_side[3], "local enabled = true", "added side")

print("diff_spec: ok")
