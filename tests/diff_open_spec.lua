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

local function has_line_highlight(buf, line_text, group)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for index, line in ipairs(lines) do
    if line:find(line_text, 1, true) then
      local marks = vim.api.nvim_buf_get_extmarks(buf, -1, { index - 1, 0 }, { index - 1, -1 }, {
        details = true,
      })
      for _, mark in ipairs(marks) do
        local details = mark[4] or {}
        if details.line_hl_group == group or details.hl_group == group then
          return true
        end
      end
    end
  end
  return false
end

local function has_syntax_highlight(buf, line_text, language)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for index, line in ipairs(lines) do
    if line:find(line_text, 1, true) then
      local marks = vim.api.nvim_buf_get_extmarks(buf, -1, { index - 1, 0 }, { index - 1, -1 }, {
        details = true,
      })
      for _, mark in ipairs(marks) do
        local details = mark[4] or {}
        if details.hl_group and details.hl_group:match("^@.*%." .. language .. "$") then
          return true
        end
      end
    end
  end
  return false
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
vim.fn.mkdir(tmp .. "/.code_reader/diffs", "p")
vim.fn.mkdir(tmp .. "/src", "p")

local source_file = tmp .. "/src/app.lua"
local diff_file = tmp .. "/.code_reader/diffs/change.diff"
local explanation_file = tmp .. "/.code_reader/diffs/change.md"

vim.fn.writefile({
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
}, source_file)

vim.fn.writefile({
  "diff --git a/src/app.lua b/src/app.lua",
  "index 1111111..2222222 100644",
  "--- a/src/app.lua",
  "+++ b/src/app.lua",
  "@@ -1,4 +1,5 @@",
  " local M = {}",
  "-local enabled = false",
  "+local enabled = true",
  "+local mode = \"fast\"",
  " ",
  " return M",
  "@@ -8,3 +9,3 @@",
  " function M.name()",
  "-  return \"old\"",
  "+  return \"new\"",
  " end",
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
  "The flag becomes enabled.",
  "",
  "---",
  "# 2. Rename value",
  "",
  "Diff: `src/app.lua#H2`",
  "",
  "The name result changes.",
}, explanation_file)

vim.cmd("edit " .. vim.fn.fnameescape(source_file))
local initial_code_buf = vim.api.nvim_get_current_buf()
local code_reader = require("code_reader")
vim.cmd("CodeReaderOpen " .. vim.fn.fnameescape(explanation_file))

local state = code_reader.state()
eq(state.doc.frontmatter.type, "code-reader-diff", "diff doc type")
eq(vim.api.nvim_win_is_valid(state.windows.diff_after), true, "diff after window valid")

local front_page = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows.code), 0, -1, false), "\n")
contains(front_page, "## Diff Coverage", "coverage heading")
contains(front_page, "Explained changes: 5 / 5 (100.0%)", "coverage ratio")
contains(front_page, "Explained hunks: 2 / 2", "hunk coverage")
eq(has_highlight(vim.api.nvim_win_get_buf(state.windows.code), "[[1|Toggle flag]]", "CodeReaderStepLink"), true, "diff front page step link highlighted")

code_reader.next()
local explanation = table.concat(vim.api.nvim_buf_get_lines(state.buffers.explanation, 0, -1, false), "\n")
contains(explanation, "Diff: src/app.lua#H1", "diff source header")
contains(explanation, "View: full file side-by-side", "full view header")
contains(explanation, "Status: applies", "applies header")
contains(explanation, "Before: `src/app.lua#L1-L4`", "before range")
contains(explanation, "After: `src/app.lua#L1-L5`", "after range")
contains(explanation, "- Next: [[2|Rename value]] (↓8 src/app.lua#H2)", "diff next navigation position")
contains(explanation, "- Diff: `src/app.lua#H1`", "diff navigation source")
eq(has_highlight(state.buffers.explanation, "Diff: src/app.lua#H1", "CodeReaderDiffTarget"), true, "diff header highlighted")
eq(has_highlight(state.buffers.explanation, "- Diff: `src/app.lua#H1`", "CodeReaderDiffTarget"), true, "diff navigation highlighted")
eq(has_highlight(state.buffers.explanation, "[[2|Rename value]]", "CodeReaderStepLink"), true, "diff navigation step link highlighted")

local before_text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows.code), 0, -1, false), "\n")
local after_text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows.diff_after), 0, -1, false), "\n")
contains(before_text, "local enabled = false", "before full content")
contains(after_text, "local enabled = true", "after full content")
contains(after_text, "local mode = \"fast\"", "after added content")
contains(before_text, "~ local enabled = false", "before modified marker")
contains(after_text, "~ local enabled = true", "after modified marker")
contains(after_text, "+ local mode = \"fast\"", "after added marker")
eq(has_line_highlight(vim.api.nvim_win_get_buf(state.windows.code), 'return "old"', "CodeReaderDimLine"), true, "unrelated hunk dimmed")
eq(has_line_highlight(vim.api.nvim_win_get_buf(state.windows.code), "local M = {}", "CodeReaderActiveLine"), true, "focused context active")
eq(has_line_highlight(vim.api.nvim_win_get_buf(state.windows.code), "function M.name()", "CodeReaderDimLine"), true, "unrelated context dimmed")
eq(has_line_highlight(vim.api.nvim_win_get_buf(state.windows.code), "local enabled = false", "CodeReaderDiffModify"), true, "focused modified remains highlighted")
eq(has_syntax_highlight(vim.api.nvim_win_get_buf(state.windows.code), "local enabled = false", "lua"), true, "before diff syntax highlighted")
eq(has_syntax_highlight(vim.api.nvim_win_get_buf(state.windows.diff_after), "local enabled = true", "lua"), true, "after diff syntax highlighted")

code_reader.toggle_focus()
eq(has_line_highlight(vim.api.nvim_win_get_buf(state.windows.code), 'return "old"', "CodeReaderDimLine"), false, "focus toggle removes diff dimming")
code_reader.toggle_focus()

local before_marks = vim.api.nvim_buf_get_extmarks(vim.api.nvim_win_get_buf(state.windows.code), -1, 0, -1, {
  details = true,
})
local has_word_mark = false
for _, mark in ipairs(before_marks) do
  local details = mark[4] or {}
  if details.hl_group == "CodeReaderDiffWord" then
    has_word_mark = true
    break
  end
end
eq(has_word_mark, true, "modified word highlight")

vim.fn.writefile({
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
}, source_file)
code_reader.goto_step(2)
local applied_explanation = table.concat(vim.api.nvim_buf_get_lines(state.buffers.explanation, 0, -1, false), "\n")
contains(applied_explanation, "View: full file side-by-side", "already applied full view")
contains(applied_explanation, "Status: already-applied", "already applied header")
local applied_before = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows.code), 0, -1, false), "\n")
contains(applied_before, "local enabled = false", "already applied reconstructed before")

vim.fn.writefile({ "unrelated" }, source_file)
code_reader.goto_step(2)
local stale_explanation = table.concat(vim.api.nvim_buf_get_lines(state.buffers.explanation, 0, -1, false), "\n")
contains(stale_explanation, "View: patch-only side-by-side", "stale fallback header")
contains(stale_explanation, "Status: stale", "stale header")

local stale_before = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows.code), 0, -1, false), "\n")
local stale_after = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows.diff_after), 0, -1, false), "\n")
contains(stale_before, "local enabled = false", "stale before hunk")
contains(stale_after, "local enabled = true", "stale after hunk")
contains(stale_before, "~ local enabled = false", "stale before modified marker")
contains(stale_after, "+ local mode = \"fast\"", "stale after add marker")
eq(has_syntax_highlight(vim.api.nvim_win_get_buf(state.windows.code), "local enabled = false", "lua"), true, "stale before syntax highlighted")
eq(has_syntax_highlight(vim.api.nvim_win_get_buf(state.windows.diff_after), "local mode = \"fast\"", "lua"), true, "stale after syntax highlighted")

vim.cmd("CodeReaderClose")
eq(vim.api.nvim_get_current_buf(), initial_code_buf, "initial code buffer restored")

print("diff_open_spec: ok")
