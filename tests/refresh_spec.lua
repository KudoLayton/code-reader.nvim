vim.opt.runtimepath:append(vim.fn.getcwd())
vim.cmd("runtime plugin/code_reader.lua")

local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)), 2)
  end
end

local function contains(lines, needle, label)
  eq(table.concat(lines, "\n"):find(needle, 1, true) ~= nil, true, label)
end

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/.code_reader/diffs", "p")
vim.fn.mkdir(tmp .. "/src", "p")

local source_file = tmp .. "/src/app.lua"
local explanation_file = tmp .. "/.code_reader/flow.md"
local diff_file = tmp .. "/.code_reader/diffs/change.diff"
local diff_explanation_file = tmp .. "/.code_reader/diffs/change.md"

vim.fn.writefile({
  "local M = {}",
  "function M.first()",
  "  return true",
  "end",
  "return M",
}, source_file)

local function write_source_explanation(include_second, body)
  local lines = {
    "---",
    "type: code-reader",
    "version: 1",
    "---",
    "",
    "<!-- code-reader: front-page -->",
    "# Refresh overview",
    "",
    "Refresh the walkthrough without reopening its windows.",
    "",
    "---",
    "# 1. First step",
    "",
    "Source: `src/app.lua#L1-L2`",
    "",
    "The module is initialized.",
  }
  if include_second then
    vim.list_extend(lines, {
      "",
      "---",
      "# 2. Second step",
      "",
      "Source: `src/app.lua#L2-L4`",
      "Cursor: `src/app.lua#L3`",
      "",
      body,
    })
  end
  vim.fn.writefile(lines, explanation_file)
end

write_source_explanation(true, "The first implementation is shown.")
vim.cmd("edit " .. vim.fn.fnameescape(source_file))
vim.cmd("CodeReaderOpen " .. vim.fn.fnameescape(explanation_file))

local code_reader = require("code_reader")
local state = code_reader.state()
code_reader.goto_step(3)
eq(state.current, 3, "second step selected before refresh")
eq(vim.api.nvim_win_get_cursor(state.windows.code)[1], 3, "initial cursor uses directive")

write_source_explanation(true, "The refreshed implementation is shown.")
vim.cmd("CodeReaderRefresh")
eq(state.current, 3, "refresh preserves matching step id")
contains(vim.api.nvim_buf_get_lines(state.buffers.explanation, 0, -1, false), "The refreshed implementation is shown.", "refreshed body renders")

write_source_explanation(false, "")
vim.cmd("CodeReaderRefresh")
eq(state.current, 1, "refresh falls back to front page when step disappears")

local preserved_doc = state.doc
vim.fn.writefile({
  "---",
  "type: code-reader-diff",
  "version: 1",
  "diff: ./missing.diff",
  "---",
}, explanation_file)
local failed_refresh = pcall(vim.cmd, "CodeReaderRefresh")
eq(failed_refresh, false, "failed refresh reports an error")
eq(state.doc, preserved_doc, "failed refresh keeps existing document")
eq(state.current, 1, "failed refresh keeps selected step")
vim.cmd("CodeReaderClose")

vim.fn.writefile({
  "--- a/src/app.lua",
  "+++ b/src/app.lua",
  "@@ -1 +1 @@",
  "-local old = true",
  "+local new = true",
}, diff_file)
vim.fn.writefile({
  "---",
  "type: code-reader-diff",
  "version: 1",
  "diff: ./change.diff",
  "---",
  "",
  "<!-- code-reader: front-page -->",
  "# Diff refresh overview",
  "",
  "Explain the change.",
  "",
  "---",
  "# 1. Change value",
  "",
  "Diff: `src/app.lua#H1`",
  "",
  "The assignment changes.",
}, diff_explanation_file)
vim.cmd("edit " .. vim.fn.fnameescape(source_file))
vim.cmd("CodeReaderOpen " .. vim.fn.fnameescape(diff_explanation_file))

vim.fn.writefile({
  "--- a/src/app.lua",
  "+++ b/src/app.lua",
  "@@ -1 +1 @@",
  "-local old = true",
  "+local refreshed = true",
}, diff_file)
vim.cmd("CodeReaderRefresh")
state = code_reader.state()
local diff_lines = {}
for _, entry in ipairs(state.diff.files[1].hunks[1].lines) do
  table.insert(diff_lines, entry.text)
end
contains(diff_lines, "local refreshed = true", "refresh reloads linked diff")
vim.cmd("CodeReaderClose")

print("refresh_spec: ok")
