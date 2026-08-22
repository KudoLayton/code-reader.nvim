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

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local smooth_scroll_calls = {}
package.preload["neoscroll"] = function()
  return {
    zt = function(opts)
      table.insert(smooth_scroll_calls, opts or {})
      if opts and opts.winid then
        vim.api.nvim_win_call(opts.winid, function()
          vim.cmd("normal! zt")
        end)
      end
    end,
  }
end

local function window_view(win)
  local current = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(win)
  local view = vim.fn.winsaveview()
  vim.api.nvim_set_current_win(current)
  return view
end

local function sync_window_to_line(win, line)
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_cursor(win, { line, 0 })
  vim.cmd("doautocmd CursorMoved")
  vim.cmd("normal! zt")
  vim.cmd("doautocmd WinScrolled")
  vim.cmd("redraw")
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

local function has_highlight_priority_at_least(buf, line_text, group, priority)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for index, line in ipairs(lines) do
    if line:find(line_text, 1, true) then
      local marks = vim.api.nvim_buf_get_extmarks(buf, -1, { index - 1, 0 }, { index - 1, -1 }, {
        details = true,
      })
      for _, mark in ipairs(marks) do
        local details = mark[4] or {}
        if details.hl_group == group and (details.priority or 0) >= priority then
          return true
        end
      end
    end
  end
  return false
end

local function has_line_hl_group(buf, line_text, group)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for index, line in ipairs(lines) do
    if line:find(line_text, 1, true) then
      local marks = vim.api.nvim_buf_get_extmarks(buf, -1, { index - 1, 0 }, { index - 1, -1 }, {
        details = true,
      })
      for _, mark in ipairs(marks) do
        local details = mark[4] or {}
        if details.line_hl_group == group then
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

local function has_syntax_at_text_start(buf, line_text, language)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for index, line in ipairs(lines) do
    local start_index = line:find(line_text, 1, true)
    if start_index then
      local start_col = start_index - 1
      local marks = vim.api.nvim_buf_get_extmarks(buf, -1, { index - 1, start_col }, { index - 1, start_col + 1 }, {
        details = true,
      })
      for _, mark in ipairs(marks) do
        local details = mark[4] or {}
        if
          mark[3] <= start_col
          and (details.end_col or start_col) > start_col
          and details.hl_group
          and details.hl_group:match("^@.*%." .. language .. "$")
          and (details.priority or 0) >= 10000
        then
          return true
        end
      end
    end
  end
  return false
end

local function has_highlight_at_text(buf, line_text, text, group)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for index, line in ipairs(lines) do
    if line:find(line_text, 1, true) then
      local start_index = line:find(text, 1, true)
      if start_index then
        local start_col = start_index - 1
        local marks = vim.api.nvim_buf_get_extmarks(buf, -1, { index - 1, start_col }, { index - 1, start_col + #text }, {
          details = true,
        })
        for _, mark in ipairs(marks) do
          local details = mark[4] or {}
          if mark[3] == start_col and details.end_col == start_col + #text and details.hl_group == group then
            return true
          end
        end
      end
    end
  end
  return false
end

local function render_missing_language_notification()
  local syntax = require("code_reader.syntax")
  local original_filetype_for_path = syntax.filetype_for_path
  local original_language_for_filetype = syntax.language_for_filetype
  local original_notify = vim.notify
  local messages = {}
  local buf = vim.api.nvim_create_buf(false, true)
  local rows = {
    {
      before = {
        kind = "context",
        text = "int main() { return 0; }",
        text_col = 0,
      },
    },
  }

  syntax.notified_missing_languages = {}
  syntax.filetype_for_path = function()
    return "cpp"
  end
  syntax.language_for_filetype = function()
    return nil, "no parser for cpp"
  end
  vim.notify = function(message, level)
    table.insert(messages, {
      message = message,
      level = level,
    })
  end

  local missing_log = vim.fn.tempname()
  syntax.highlight_diff(buf, rows, "before", "src/missing.cpp", 0, {
    debug = {
      enabled = true,
      log_file = missing_log,
    },
  })
  syntax.highlight_diff(buf, rows, "after", "src/missing.cpp", 0, {
    debug = {
      enabled = true,
      log_file = missing_log,
    },
  })

  syntax.filetype_for_path = original_filetype_for_path
  syntax.language_for_filetype = original_language_for_filetype
  vim.notify = original_notify

  return messages, table.concat(vim.fn.readfile(missing_log), "\n")
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
local log_file = tmp .. "/code-reader.log"

local source_lines = {
  "local M = {}",
  "local enabled = false",
  "",
  "return M",
}
for index = 5, 37 do
  table.insert(source_lines, "-- filler " .. tostring(index))
end
vim.list_extend(source_lines, {
  "function M.name()",
  "  return \"old\"",
  "end",
})
vim.fn.writefile(source_lines, source_file)

local diff_lines = {
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
}
vim.list_extend(diff_lines, {
  "@@ -38,3 +39,3 @@",
  " function M.name()",
  "-  return \"old\"",
  "+  return \"new\"",
  " end",
  "diff --git a/src/created.lua b/src/created.lua",
  "new file mode 100644",
  "index 0000000..3333333",
  "--- /dev/null",
  "+++ b/src/created.lua",
  "@@ -0,0 +1,2 @@",
  "+local created = true",
  "+return created",
  "diff --git a/src/obsolete.lua b/src/obsolete.lua",
  "deleted file mode 100644",
  "index 4444444..0000000",
  "--- a/src/obsolete.lua",
  "+++ /dev/null",
  "@@ -1,12 +0,0 @@",
  "-local keep_1 = true",
  "-local keep_2 = true",
  "-local keep_3 = true",
  "-local keep_4 = true",
  "-local keep_5 = true",
  "-local keep_6 = true",
  "-local keep_7 = true",
  "-local keep_8 = true",
  "-local keep_9 = true",
  "-local keep_10 = true",
  "-local obsolete = true",
  "-return obsolete",
})
vim.fn.writefile(diff_lines, diff_file)

vim.fn.writefile({
  "---",
  "type: code-reader-diff",
  "version: 2",
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
  "",
  "---",
  "# 3. Toggle neighborhood",
  "",
  "Diff: `src/app.lua#H1@new:padding=1`",
  "",
  "Show one line around the first hunk.",
  "",
  "---",
  "# 4. Add created module",
  "",
  "Diff: `src/created.lua#H1`",
  "",
  "The module is added.",
  "",
  "---",
  "# 5. Remove obsolete module",
  "",
  "Diff: `src/obsolete.lua#H1@old:L11-L12`",
  "",
  "The module is deleted.",
}, explanation_file)

vim.cmd("edit " .. vim.fn.fnameescape(source_file))
local initial_code_buf = vim.api.nvim_get_current_buf()
local code_reader = require("code_reader")
code_reader.setup({
  debug = {
    enabled = true,
    log_file = log_file,
  },
})
vim.cmd("CodeReaderOpen " .. vim.fn.fnameescape(explanation_file))

local state = code_reader.state()
eq(state.doc.frontmatter.type, "code-reader-diff", "diff doc type")
eq(valid_win(state.windows.diff_after), nil, "front page starts as one-column diff view")

local front_page = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows.code), 0, -1, false), "\n")
contains(front_page, "## Diff Coverage", "coverage heading")
contains(front_page, "Explained changes: 9 / 19 (47.4%)", "coverage ratio")
contains(front_page, "Explained hunks: 3 / 4", "hunk coverage")
eq(has_highlight(vim.api.nvim_win_get_buf(state.windows.code), "[[1|Toggle flag]]", "CodeReaderStepLink"), true, "diff front page step link highlighted")

code_reader.next()
eq(valid_win(state.windows.diff_after), true, "two-sided diff creates after window")
eq(window_view(state.windows.code).topline, vim.api.nvim_win_get_cursor(state.windows.code)[1], "two-sided diff before starts at focused row")
eq(window_view(state.windows.diff_after).topline, vim.api.nvim_win_get_cursor(state.windows.diff_after)[1], "two-sided diff after starts at focused row")
local explanation = table.concat(vim.api.nvim_buf_get_lines(state.buffers.explanation, 0, -1, false), "\n")
contains(explanation, "Diff: src/app.lua#H1", "diff source header")
contains(explanation, "View: full file side-by-side", "full view header")
contains(explanation, "Status: applies", "applies header")
contains(explanation, "Before: `src/app.lua#L1-L4`", "before range")
contains(explanation, "After: `src/app.lua#L1-L5`", "after range")
contains(explanation, "- Next: [[2|Rename value]] (↓38 src/app.lua#H2)", "diff next navigation position")
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
eq(has_highlight_priority_at_least(vim.api.nvim_win_get_buf(state.windows.code), 'return "old"', "CodeReaderDimLine", 11000), true, "unrelated hunk dimming overrides syntax")
eq(has_line_highlight(vim.api.nvim_win_get_buf(state.windows.code), "local M = {}", "CodeReaderActiveLine"), true, "focused context active")
eq(has_line_highlight(vim.api.nvim_win_get_buf(state.windows.code), "function M.name()", "CodeReaderDimLine"), true, "unrelated context dimmed")
eq(has_line_highlight(vim.api.nvim_win_get_buf(state.windows.code), "local enabled = false", "CodeReaderDiffModify"), true, "focused modified remains highlighted")
eq(has_line_hl_group(vim.api.nvim_win_get_buf(state.windows.code), "local M = {}", "CodeReaderActiveLine"), false, "diff context avoids line_hl_group")
eq(has_line_hl_group(vim.api.nvim_win_get_buf(state.windows.code), "local enabled = false", "CodeReaderDiffModify"), false, "diff modified avoids line_hl_group")
eq(has_syntax_highlight(vim.api.nvim_win_get_buf(state.windows.code), "local enabled = false", "lua"), true, "before diff syntax highlighted")
eq(has_syntax_highlight(vim.api.nvim_win_get_buf(state.windows.diff_after), "local enabled = true", "lua"), true, "after diff syntax highlighted")
eq(has_syntax_at_text_start(vim.api.nvim_win_get_buf(state.windows.code), "local enabled = false", "lua"), true, "before diff first character highlighted")
eq(has_syntax_at_text_start(vim.api.nvim_win_get_buf(state.windows.diff_after), "local enabled = true", "lua"), true, "after diff first character highlighted")
local debug_log = table.concat(vim.fn.readfile(log_file), "\n")
contains(debug_log, "syntax.diff", "debug log records diff syntax event")
contains(debug_log, "path=src/app.lua", "debug log records diff path")
contains(debug_log, "language=lua", "debug log records diff language")
eq(vim.api.nvim_get_option_value("scrollbind", { win = state.windows.code }), false, "before diff native scrollbind disabled")
eq(vim.api.nvim_get_option_value("scrollbind", { win = state.windows.diff_after }), false, "after diff native scrollbind disabled")
eq(vim.api.nvim_get_option_value("cursorbind", { win = state.windows.code }), false, "before diff native cursorbind disabled")
eq(vim.api.nvim_get_option_value("cursorbind", { win = state.windows.diff_after }), false, "after diff native cursorbind disabled")
eq(vim.api.nvim_get_option_value("scrollbind", { win = state.windows.explanation }), false, "explanation native scrollbind disabled")
eq(vim.api.nvim_get_option_value("cursorbind", { win = state.windows.explanation }), false, "explanation native cursorbind disabled")
eq(vim.api.nvim_get_option_value("scrollbind", { win = state.windows.toc }), false, "toc native scrollbind disabled")
eq(vim.api.nvim_get_option_value("cursorbind", { win = state.windows.toc }), false, "toc native cursorbind disabled")
eq(vim.api.nvim_win_get_cursor(state.windows.code)[1], vim.api.nvim_win_get_cursor(state.windows.diff_after)[1], "initial diff cursors match")
eq(window_view(state.windows.code).topline, window_view(state.windows.diff_after).topline, "initial diff toplines match")

sync_window_to_line(state.windows.code, 30)
eq(vim.api.nvim_win_get_cursor(state.windows.diff_after)[1], 30, "after diff cursor follows before")
eq(window_view(state.windows.diff_after).topline, window_view(state.windows.code).topline, "after diff viewport follows before")

sync_window_to_line(state.windows.diff_after, 3)
eq(vim.api.nvim_win_get_cursor(state.windows.code)[1], 3, "before diff cursor follows after")
eq(window_view(state.windows.code).topline, window_view(state.windows.diff_after).topline, "before diff viewport follows after")

local current_step_before_toc_move = state.current
local before_cursor_before_toc_move = vim.api.nvim_win_get_cursor(state.windows.code)[1]
local after_cursor_before_toc_move = vim.api.nvim_win_get_cursor(state.windows.diff_after)[1]
local explanation_cursor_before_toc_move = vim.api.nvim_win_get_cursor(state.windows.explanation)[1]
vim.api.nvim_set_current_win(state.windows.toc)
vim.api.nvim_win_set_cursor(state.windows.toc, { 4, 0 })
vim.cmd("doautocmd CursorMoved")
vim.cmd("redraw")
eq(state.current, current_step_before_toc_move, "toc cursor move does not change step")
eq(vim.api.nvim_win_get_cursor(state.windows.code)[1], before_cursor_before_toc_move, "toc cursor move does not move before diff")
eq(vim.api.nvim_win_get_cursor(state.windows.diff_after)[1], after_cursor_before_toc_move, "toc cursor move does not move after diff")
eq(vim.api.nvim_win_get_cursor(state.windows.explanation)[1], explanation_cursor_before_toc_move, "toc cursor move does not move explanation")

code_reader.activate()
eq(state.current, 4, "toc activation changes step")
eq(vim.api.nvim_win_get_cursor(state.windows.code)[1], vim.api.nvim_win_get_cursor(state.windows.diff_after)[1], "toc activation moves diff cursors together")
eq(vim.api.nvim_get_current_win(), state.windows.toc, "toc activation keeps focus")
code_reader.goto_step(2)
local missing_messages, missing_log = render_missing_language_notification()
eq(#missing_messages, 1, "missing Tree-sitter parser notifies once per path")
contains(missing_messages[1].message, "Tree-sitter parser is unavailable for cpp", "missing parser notification explains parser")
contains(missing_messages[1].message, "Diff syntax highlighting is disabled for this file.", "missing parser notification explains impact")
contains(missing_log, "reason=no parser for cpp", "missing parser log records reason")
eq(has_highlight_at_text(vim.api.nvim_win_get_buf(state.windows.code), "local enabled = false", "false", "CodeReaderDiffWord"), true, "before diff word aligns to rendered text")
eq(has_highlight_at_text(vim.api.nvim_win_get_buf(state.windows.diff_after), "local enabled = true", "true", "CodeReaderDiffWord"), true, "after diff word aligns to rendered text")

vim.cmd("CodeReaderToggleDimming")
eq(state.dimming, false, "dimming command disables diff dimming")
eq(has_line_highlight(vim.api.nvim_win_get_buf(state.windows.code), 'return "old"', "CodeReaderDimLine"), false, "dimming command removes diff dimming")
eq(has_line_highlight(vim.api.nvim_win_get_buf(state.windows.code), "local enabled = false", "CodeReaderDiffModify"), true, "focused diff highlight remains without dimming")
eq(code_reader.toggle_dimming(true), true, "dimming api enables diff dimming")
eq(has_line_highlight(vim.api.nvim_win_get_buf(state.windows.code), 'return "old"', "CodeReaderDimLine"), true, "dimming api restores diff dimming")

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
    eq((details.priority or 0) < 10000, true, "modified word highlight stays below syntax")
    has_word_mark = true
    break
  end
end
eq(has_word_mark, true, "modified word highlight")

local smooth_before_same_diff = #smooth_scroll_calls
code_reader.goto_step(4)
eq(#smooth_scroll_calls, smooth_before_same_diff + 2, "same diff file two-column uses smooth scroll")
eq(smooth_scroll_calls[#smooth_scroll_calls - 1].winid, state.windows.code, "before diff smooth scroll targets code window")
eq(smooth_scroll_calls[#smooth_scroll_calls].winid, state.windows.diff_after, "after diff smooth scroll targets after window")
local range_explanation = table.concat(vim.api.nvim_buf_get_lines(state.buffers.explanation, 0, -1, false), "\n")
contains(range_explanation, "Diff: src/app.lua#H1@new:padding=1", "range diff source header")
contains(range_explanation, "After: `src/app.lua#L1-L6`", "range after label")
local range_before = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows.code), 0, -1, false), "\n")
local range_after = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows.diff_after), 0, -1, false), "\n")
contains(range_before, "local enabled = false", "range before content")
contains(range_after, "local enabled = true", "range after content")
contains(range_after, "return M", "range includes trailing padding")
contains(range_after, 'return "new"', "range keeps full file diff")
eq(has_line_highlight(vim.api.nvim_win_get_buf(state.windows.code), 'return "old"', "CodeReaderDimLine"), true, "range dims outside focus")
eq(has_line_highlight(vim.api.nvim_win_get_buf(state.windows.code), "local enabled = false", "CodeReaderDiffModify"), true, "range keeps focused change highlighted")

vim.fn.writefile({
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
}, source_file)
code_reader.goto_step(4)
local hunk_only_explanation = table.concat(vim.api.nvim_buf_get_lines(state.buffers.explanation, 0, -1, false), "\n")
contains(hunk_only_explanation, "View: selected hunk side-by-side", "selected hunk full file header")
contains(hunk_only_explanation, "Status: applies", "selected hunk status")
local hunk_only_after = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows.diff_after), 0, -1, false), "\n")
contains(hunk_only_after, "local enabled = true", "selected hunk applied")
contains(hunk_only_after, 'return "custom"', "selected hunk preserves unrelated current content")

local applied_source_lines = {
  "local M = {}",
  "local enabled = true",
  "local mode = \"fast\"",
  "",
  "return M",
}
for index = 5, 37 do
  table.insert(applied_source_lines, "-- filler " .. tostring(index))
end
vim.list_extend(applied_source_lines, {
  "function M.name()",
  "  return \"new\"",
  "end",
})
vim.fn.writefile(applied_source_lines, source_file)
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

code_reader.goto_step(1)
eq(valid_win(state.windows.diff_after), nil, "front page closes diff after window")
eq(vim.api.nvim_get_option_value("scrollbind", { win = state.windows.code }), false, "front page clears primary scrollbind")
eq(vim.api.nvim_get_option_value("cursorbind", { win = state.windows.code }), false, "front page clears primary cursorbind")

code_reader.goto_step(5)
eq(valid_win(state.windows.diff_after), nil, "added file renders as one-column diff view")
eq(vim.api.nvim_get_option_value("scrollbind", { win = state.windows.code }), false, "one-sided diff clears primary scrollbind")
eq(vim.api.nvim_get_option_value("cursorbind", { win = state.windows.code }), false, "one-sided diff clears primary cursorbind")
local added_text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows.code), 0, -1, false), "\n")
contains(added_text, "+ local created = true", "added file content in primary code window")

code_reader.goto_step(6)
eq(valid_win(state.windows.diff_after), nil, "deleted file renders as one-column diff view")
local deleted_text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows.code), 0, -1, false), "\n")
contains(deleted_text, "- local obsolete = true", "deleted file content in primary code window")
eq(vim.api.nvim_win_get_cursor(state.windows.code)[1], 11, "deleted file range cursor moves to focused deletion")
eq(window_view(state.windows.code).topline, 11, "deleted file viewport starts at focused deletion")

local smooth_before_single_column = #smooth_scroll_calls
code_reader.goto_step(6)
eq(#smooth_scroll_calls, smooth_before_single_column + 1, "same single-column diff uses smooth scroll")
eq(smooth_scroll_calls[#smooth_scroll_calls].winid, state.windows.code, "single-column diff smooth scroll targets code window")

code_reader.goto_step(2)
local closed_after = state.windows.diff_after
vim.api.nvim_win_close(closed_after, true)
eq(valid_win(closed_after), false, "test closed diff after window")
code_reader.goto_step(3)
eq(valid_win(state.windows.diff_after), true, "two-sided diff recreates closed after window")

local closed_code = state.windows.code
vim.api.nvim_win_close(closed_code, true)
eq(valid_win(closed_code), false, "test closed primary code window")
code_reader.goto_step(5)
eq(valid_win(state.windows.code), true, "one-sided diff recreates closed primary code window")
eq(valid_win(state.windows.diff_after), nil, "one-sided recovery keeps diff after closed")
local recovered_added = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows.code), 0, -1, false), "\n")
contains(recovered_added, "+ local created = true", "recovered primary code window content")

vim.cmd("CodeReaderClose")
eq(vim.api.nvim_get_current_buf(), initial_code_buf, "initial code buffer restored")

local cpp_parser_ok = pcall(vim.treesitter.get_string_parser, "int main() { return 0; }", "cpp")
local cpp_query_ok = false
if cpp_parser_ok then
  local ok, query = pcall(vim.treesitter.query.get, "cpp", "highlights")
  cpp_query_ok = ok and query ~= nil
end
if cpp_query_ok then
  local cpp_source_file = tmp .. "/src/app.cpp"
  local cpp_diff_file = tmp .. "/.code_reader/diffs/change-cpp.diff"
  local cpp_explanation_file = tmp .. "/.code_reader/diffs/change-cpp.md"

  vim.fn.writefile({
    "int main() {",
    "  return 0;",
    "}",
  }, cpp_source_file)

  vim.fn.writefile({
    "diff --git a/src/app.cpp b/src/app.cpp",
    "index 1111111..2222222 100644",
    "--- a/src/app.cpp",
    "+++ b/src/app.cpp",
    "@@ -1,3 +1,3 @@",
    " int main() {",
    "-  return 0;",
    "+  return 1;",
    " }",
  }, cpp_diff_file)

  vim.fn.writefile({
    "---",
    "type: code-reader-diff",
    "version: 2",
    "diff: ./change-cpp.diff",
    "---",
    "",
    "<!-- code-reader: front-page -->",
    "# C++ Diff Overview",
    "",
    "---",
    "# 1. Change return value",
    "",
    "Diff: `src/app.cpp#H1`",
  }, cpp_explanation_file)

  vim.cmd("CodeReaderOpen " .. vim.fn.fnameescape(cpp_explanation_file))
  code_reader.next()
  eq(has_syntax_highlight(vim.api.nvim_win_get_buf(code_reader.state().windows.code), "return 0", "cpp"), true, "C++ before diff syntax highlighted")
  eq(has_syntax_highlight(vim.api.nvim_win_get_buf(code_reader.state().windows.diff_after), "return 1", "cpp"), true, "C++ after diff syntax highlighted")
  vim.cmd("CodeReaderClose")
end

print("diff_open_spec: ok")
