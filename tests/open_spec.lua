vim.opt.runtimepath:append(vim.fn.getcwd())
vim.cmd("runtime plugin/code_reader.lua")

local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)), 2)
  end
end

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/.code_reader", "p")
vim.fn.mkdir(tmp .. "/src", "p")

local source_file = tmp .. "/src/app.lua"
local explanation_file = tmp .. "/.code_reader/flow.md"

vim.fn.writefile({
  "local M = {}",
  "function M.run()",
  "  return true",
  "end",
  "return M",
}, source_file)

vim.fn.writefile({
  "---",
  "type: code-reader",
  "version: 1",
  "---",
  "",
  "# 1. Module setup",
  "",
  "Source: `src/app.lua#L1-L2`",
  "",
  "The module table is prepared.",
  "",
  "---",
  "## 1.1. Run function",
  "",
  "Source: `src/app.lua#L2-L4`",
  "",
  "The call-stack detail for run.",
  "",
  "---",
  "### 1.1.1. Return value",
  "",
  "Source: `src/app.lua#L3-L3`",
  "",
  "The function returns true.",
}, explanation_file)

vim.cmd("edit " .. vim.fn.fnameescape(source_file))
vim.cmd("CodeReaderOpen " .. vim.fn.fnameescape(explanation_file))

local code_reader = require("code_reader")
local state = code_reader.state()

eq(#state.doc.steps, 3, "opened step count")
eq(state.current, 1, "initial step")
eq(vim.api.nvim_win_is_valid(state.windows.code), true, "code window valid")
eq(vim.api.nvim_win_is_valid(state.windows.explanation), true, "explanation window valid")
eq(vim.api.nvim_win_is_valid(state.windows.toc), true, "toc window valid")
eq(vim.api.nvim_buf_get_lines(state.buffers.explanation, 0, 1, false)[1], "# 1 Module setup", "initial explanation title")

code_reader.next()
eq(state.current, 2, "next step")
eq(vim.api.nvim_buf_get_lines(state.buffers.explanation, 0, 1, false)[1], "# 1.1 Run function", "next explanation title")

code_reader.prev()
eq(state.current, 1, "previous step")

vim.api.nvim_set_current_win(state.windows.toc)
vim.api.nvim_win_set_cursor(state.windows.toc, { 3, 0 })
code_reader.activate()
eq(state.current, 3, "toc activation step")
eq(vim.api.nvim_buf_get_lines(state.buffers.explanation, 0, 1, false)[1], "# 1.1.1 Return value", "toc sync explanation title")
eq(vim.api.nvim_win_get_cursor(state.windows.explanation)[1], 1, "toc sync explanation cursor")
eq(vim.api.nvim_get_current_win(), state.windows.toc, "toc focus stays")

code_reader.goto_step(2)
local explanation_lines = vim.api.nvim_buf_get_lines(state.buffers.explanation, 0, -1, false)
local joined = table.concat(explanation_lines, "\n")
eq(joined:find("## Navigation", 1, true) ~= nil, true, "navigation heading")
eq(joined:find("- Previous: [[1|Module setup]]", 1, true) ~= nil, true, "previous navigation link")
eq(joined:find("- Next: [[1.1.1|Return value]]", 1, true) ~= nil, true, "next navigation link")
eq(joined:find("- Parent: [[1|Module setup]]", 1, true) ~= nil, true, "parent navigation link")
eq(joined:find("- Children:", 1, true) ~= nil, true, "children navigation list")
eq(joined:find("  - [[1.1.1|Return value]]", 1, true) ~= nil, true, "child navigation link")
eq(joined:find("- Source: `src/app.lua#L2-L4`", 1, true) ~= nil, true, "source navigation link")

local code_win = state.windows.code
local explanation_win = state.windows.explanation
local toc_win = state.windows.toc
vim.cmd("CodeReaderClose")
eq(vim.api.nvim_win_is_valid(code_win), true, "code window remains after close")
eq(vim.api.nvim_win_is_valid(explanation_win), false, "explanation window closes")
eq(vim.api.nvim_win_is_valid(toc_win), false, "toc window closes")
eq(code_reader.state().doc, nil, "state clears doc")

vim.cmd("CodeReaderClose")

print("open_spec: ok")
