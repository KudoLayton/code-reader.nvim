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
  "local function run()",
  "  return true",
  "end",
  "",
  "run()",
}, source_file)

vim.fn.writefile({
  "---",
  "type: code-reader",
  "version: 1",
  "---",
  "",
  "# 1. Module setup",
  "",
  "Source: `src/app.lua#L1-L5`",
  "",
  "Jump to [[1.1|run detail]].",
  "",
  "[run](<treesitter://src/app.lua?query=(identifier) @code_reader.symbol>)",
  "",
  "---",
  "## 1.1. Run detail",
  "",
  "Source: `src/app.lua#L1-L5`",
  "",
  "The run symbol is used here.",
}, explanation_file)

vim.cmd("edit " .. vim.fn.fnameescape(source_file))
vim.cmd("CodeReaderOpen " .. vim.fn.fnameescape(explanation_file))

local code_reader = require("code_reader")
local symbols = require("code_reader.symbols")
local state = code_reader.state()

local explanation = state.buffers.explanation
vim.api.nvim_set_current_win(state.windows.explanation)
vim.api.nvim_win_set_cursor(state.windows.explanation, { 9, 10 })
code_reader.activate()
eq(state.current, 2, "internal link moves to target step")

code_reader.goto_step(1)
vim.api.nvim_set_current_win(state.windows.explanation)
vim.api.nvim_set_option_value("modifiable", true, { buf = explanation })
vim.api.nvim_buf_set_lines(explanation, 8, 9, false, {
  "Jump to [[9.9|missing detail]].",
})
vim.api.nvim_set_option_value("modifiable", false, { buf = explanation })
vim.api.nvim_win_set_cursor(state.windows.explanation, { 9, 10 })
code_reader.activate()
eq(state.current, 1, "missing internal link keeps current step")

vim.api.nvim_set_current_win(state.windows.explanation)
vim.api.nvim_win_set_cursor(state.windows.explanation, { 11, 2 })
code_reader.activate()

local source_buf = vim.api.nvim_win_get_buf(state.windows.code)
local extmarks = vim.api.nvim_buf_get_extmarks(source_buf, symbols.namespace, 0, -1, {})
eq(#extmarks > 0, true, "symbol extmarks exist")

symbols.clear(source_buf)
eq(#vim.api.nvim_buf_get_extmarks(source_buf, symbols.namespace, 0, -1, {}), 0, "symbol extmarks clear")

local lsp_count = symbols.apply_lsp_highlights(source_buf, {
  [1] = {
    result = {
      {
        kind = 2,
        range = {
          start = { line = 0, character = 15 },
          ["end"] = { line = 0, character = 18 },
        },
      },
      {
        kind = 3,
        range = {
          start = { line = 4, character = 0 },
          ["end"] = { line = 4, character = 3 },
        },
      },
    },
  },
})
eq(lsp_count, 2, "mock LSP highlight count")
eq(#vim.api.nvim_buf_get_extmarks(source_buf, symbols.namespace, 0, -1, {}), 2, "mock LSP extmarks exist")
symbols.clear(source_buf)

vim.api.nvim_set_option_value("modifiable", true, { buf = explanation })
vim.api.nvim_buf_set_lines(explanation, 10, 11, false, {
  "[bad](<treesitter://src/app.lua?query=((invalid>)",
})
vim.api.nvim_set_option_value("modifiable", false, { buf = explanation })
vim.api.nvim_win_set_cursor(state.windows.explanation, { 11, 2 })
code_reader.activate()

print("symbol_spec: ok")
