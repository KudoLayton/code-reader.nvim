vim.opt.runtimepath:append(vim.fn.getcwd())
vim.cmd("runtime plugin/code_reader.lua")

local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)), 2)
  end
end

local function contains(text, needle, label)
  eq(text:find(needle, 1, true) ~= nil, true, label)
end

local function line_with(buf, text)
  for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:find(text, 1, true) then
      return index
    end
  end
  error("line not found: " .. text, 2)
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
  "local enabled = false",
  "return M",
}, source_file)

vim.fn.writefile({
  "---",
  "type: code-reader",
  "version: 1",
  "---",
  "",
  "<!-- code-reader: front-page -->",
  "# Code Reader Overview",
  "",
  "This walkthrough introduces the flow.",
  "",
  "```mermaid",
  "flowchart TD",
  "  A --> B",
  "```",
  "",
  "---",
  "# 1. Toggle flag",
  "",
  "Source: `src/app.lua#L1-L2`",
  "",
  "The flag starts disabled.",
  "",
  "```mermaid",
  "flowchart TD",
  "  Before --> After",
  "```",
}, explanation_file)

vim.fn.writefile({
  "diff --git a/src/app.lua b/src/app.lua",
  "index 1111111..2222222 100644",
  "--- a/src/app.lua",
  "+++ b/src/app.lua",
  "@@ -1,3 +1,4 @@",
  " local M = {}",
  "-local enabled = false",
  "+local enabled = true",
  "+local mode = \"fast\"",
  " return M",
}, diff_file)

vim.fn.writefile({
  "---",
  "type: code-reader-diff",
  "version: 1",
  "diff: ./change.diff",
  "---",
  "",
  "<!-- code-reader: front-page -->",
  "# Diff Overview",
  "",
  "Explain the patch.",
  "",
  "---",
  "# 1. Toggle flag",
  "",
  "Diff: `src/app.lua#H1`",
  "",
  "The flag changes.",
}, diff_explanation_file)

local code_reader = require("code_reader")
code_reader.setup({
  mermaid = {
    command = {
      "lua",
      "-e",
      "io.read('*a'); print('rendered mermaid diagram')",
    },
  },
})

vim.cmd("edit " .. vim.fn.fnameescape(source_file))
vim.cmd("CodeReaderOpen " .. vim.fn.fnameescape(explanation_file))
local state = code_reader.state()

code_reader.next()
local source_buf = vim.api.nvim_win_get_buf(state.windows.code)
eq(code_reader.copy_ref({ bufnr = source_buf, line1 = 1, line2 = 2, register = "z", notify = false }), true, "source copy succeeds")
eq(vim.fn.getreg("z"), "src/app.lua#L1-L2", "source ref")

local explanation_buf = state.buffers.explanation
local md_line = line_with(explanation_buf, "The flag starts disabled.")
eq(code_reader.copy_ref({ bufnr = explanation_buf, line1 = md_line, line2 = md_line, register = "z", notify = false }), true, "markdown copy succeeds")
eq(vim.fn.getreg("z"), ".code_reader/flow.md#L21", "markdown ref")

local mermaid_line = line_with(explanation_buf, "rendered mermaid diagram")
eq(code_reader.copy_ref({ bufnr = explanation_buf, line1 = mermaid_line, line2 = mermaid_line, register = "z", notify = false }), true, "mermaid copy succeeds")
eq(vim.fn.getreg("z"), ".code_reader/flow.md#L23-L26", "mermaid ref expands to source block")

eq(code_reader.copy_ref({ bufnr = explanation_buf, line1 = 1, line2 = md_line, register = "z", notify = false }), true, "generated mixed copy succeeds")
contains(vim.fn.getreg("z"), "Step: 2 / 2", "generated mixed selection copies text")
contains(vim.fn.getreg("z"), "The flag starts disabled.", "generated mixed selection includes markdown text")

local front_buf = state.buffers.front_page
code_reader.goto_step(1)
local front_md_line = line_with(front_buf, "This walkthrough introduces the flow.")
eq(code_reader.copy_ref({ bufnr = front_buf, line1 = front_md_line, line2 = front_md_line, register = "z", notify = false }), true, "front markdown copy succeeds")
eq(vim.fn.getreg("z"), ".code_reader/flow.md#L9", "front markdown ref")

vim.cmd("CodeReaderClose")

vim.cmd("edit " .. vim.fn.fnameescape(source_file))
vim.cmd("CodeReaderOpen " .. vim.fn.fnameescape(diff_explanation_file))
state = code_reader.state()
code_reader.next()
local after_buf = state.buffers.diff_after
local added_line = line_with(after_buf, "local mode = \"fast\"")
eq(code_reader.copy_ref({ bufnr = after_buf, line1 = added_line, line2 = added_line, register = "z", notify = false }), true, "diff copy succeeds")
eq(vim.fn.getreg("z"), "src/app.lua#H1@new:L3", "diff after logical hunk ref")

vim.api.nvim_set_current_win(state.windows.diff_after)
vim.cmd(("silent %d,%dCodeReaderCopyRef z"):format(added_line, added_line))
eq(vim.fn.getreg("z"), "src/app.lua#H1@new:L3", "command copies ref")

vim.cmd("CodeReaderClose")

print("refcopy_spec: ok")
