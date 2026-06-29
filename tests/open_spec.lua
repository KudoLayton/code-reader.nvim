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
}, explanation_file)

vim.cmd("edit " .. vim.fn.fnameescape(source_file))
vim.cmd("CodeReaderOpen " .. vim.fn.fnameescape(explanation_file))

local code_reader = require("code_reader")
local state = code_reader.state()

eq(#state.doc.steps, 2, "opened step count")
eq(state.current, 1, "initial step")
eq(vim.api.nvim_win_is_valid(state.windows.code), true, "code window valid")
eq(vim.api.nvim_win_is_valid(state.windows.explanation), true, "explanation window valid")
eq(vim.api.nvim_win_is_valid(state.windows.toc), true, "toc window valid")

code_reader.next()
eq(state.current, 2, "next step")

code_reader.prev()
eq(state.current, 1, "previous step")

print("open_spec: ok")
