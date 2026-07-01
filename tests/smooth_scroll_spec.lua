vim.opt.runtimepath:append(vim.fn.getcwd())
vim.cmd("runtime plugin/code_reader.lua")

local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)), 2)
  end
end

local execute_after_calls = {}
local fallback_calls = 0
_G.MiniAnimate = {
  is_active = function(kind)
    return kind == "scroll"
  end,
  execute_after = function(kind, callback)
    table.insert(execute_after_calls, kind)
    callback()
  end,
}

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/.code_reader", "p")
vim.fn.mkdir(tmp .. "/src", "p")

local source_file = tmp .. "/src/sample.lua"
local walkthrough_file = tmp .. "/.code_reader/walkthrough.md"

vim.fn.writefile({
  "local M = {}",
  "",
  "function M.first()",
  "  return 1",
  "end",
  "",
  "function M.second()",
  "  return 2",
  "end",
}, source_file)

vim.fn.writefile({
  "---",
  "type: code-reader",
  "version: 1",
  "---",
  "",
  "# First",
  "",
  "Source: `src/sample.lua#L3-L5`",
  "",
  "First range.",
  "",
  "---",
  "# Second",
  "",
  "Source: `src/sample.lua#L7-L9`",
  "",
  "Second range.",
}, walkthrough_file)

local code_reader = require("code_reader")
code_reader.open(walkthrough_file)

local state = code_reader.state()
local original_win_call = vim.api.nvim_win_call
vim.api.nvim_win_call = function(win, callback)
  if win == state.windows.code then
    fallback_calls = fallback_calls + 1
  end
  return original_win_call(win, callback)
end

code_reader.goto_step(2)

vim.api.nvim_win_call = original_win_call

eq(#execute_after_calls, 1, "mini.animate execute_after used for same-file smooth scroll")
eq(execute_after_calls[1], "scroll", "mini.animate waits for scroll animation")
eq(fallback_calls > 0, true, "fallback reveal runs after mini.animate")
eq(vim.api.nvim_win_get_cursor(state.windows.code)[1], 7, "same-file navigation still reaches target line")

vim.cmd("CodeReaderClose")
_G.MiniAnimate = nil

print("smooth_scroll_spec: ok")
