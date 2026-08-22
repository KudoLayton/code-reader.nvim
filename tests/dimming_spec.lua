vim.opt.runtimepath:append(vim.fn.getcwd())
vim.cmd("runtime plugin/code_reader.lua")

local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)), 2)
  end
end

local function has_highlight(buf, line_text, group)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for index, line in ipairs(lines) do
    if line:find(line_text, 1, true) then
      local marks = vim.api.nvim_buf_get_extmarks(buf, -1, { index - 1, 0 }, { index - 1, -1 }, {
        details = true,
      })
      for _, mark in ipairs(marks) do
        local details = mark[4] or {}
        if details.hl_group == group then
          return true
        end
      end
    end
  end
  return false
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
  "version: 2",
  "---",
  "",
  "<!-- code-reader: front-page -->",
  "# Overview",
  "",
  "---",
  "# 1. Module setup",
  "",
  "Source: `src/app.lua#L1-L2`",
}, explanation_file)

vim.cmd("edit " .. vim.fn.fnameescape(source_file))
local code_reader = require("code_reader")
code_reader.setup({ dimming = false })
vim.cmd("CodeReaderOpen " .. vim.fn.fnameescape(explanation_file))
code_reader.next()

local state = code_reader.state()
local code_buf = vim.api.nvim_win_get_buf(state.windows.code)
eq(state.dimming, false, "dimming option disables dimming")
eq(has_highlight(code_buf, "local M = {}", "CodeReaderActiveLine"), true, "active range remains highlighted")
eq(has_highlight(code_buf, "return M", "CodeReaderDimLine"), false, "outside focus is not dimmed when disabled")

eq(code_reader.toggle_dimming(true), true, "dimming api enables dimming after disabled setup")
eq(has_highlight(code_buf, "return M", "CodeReaderDimLine"), true, "outside focus is dimmed after api enable")

vim.cmd("CodeReaderClose")

print("dimming_spec: ok")
