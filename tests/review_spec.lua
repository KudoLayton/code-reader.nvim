vim.opt.runtimepath:append(vim.fn.getcwd())
vim.cmd("runtime plugin/code_reader.lua")

local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)), 2)
  end
end

local function starts_with(value, prefix)
  return value:sub(1, #prefix) == prefix
end

local function write_comment(line1, line2, lines)
  vim.cmd(("%d,%dCodeReaderAddComment"):format(line1, line2))
  local buffer = vim.api.nvim_get_current_buf()
  eq(starts_with(vim.api.nvim_buf_get_name(buffer), "code-reader://review/"), true, "comment buffer opens")
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.cmd("wq")
  eq(vim.api.nvim_buf_is_valid(buffer), false, "comment buffer closes after write")
end

local function read_entries(path)
  local entries = {}
  for _, line in ipairs(vim.fn.readfile(path)) do
    table.insert(entries, vim.json.decode(line))
  end
  return entries
end

local function line_with(buffer, text)
  for index, line in ipairs(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)) do
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
local walkthrough = tmp .. "/.code_reader/flow.md"
local review_file = tmp .. "/.code_reader/flow.reviews.jsonl"
local diff_file = tmp .. "/.code_reader/diffs/change.diff"
local diff_walkthrough = tmp .. "/.code_reader/diffs/change.md"
local diff_review_file = tmp .. "/.code_reader/diffs/change.reviews.jsonl"

vim.fn.writefile({
  "local M = {}",
  "local enabled = false",
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
  "Review the implementation.",
  "",
  "---",
  "# 1. Toggle flag",
  "",
  "```code-reader",
  "kind: stage",
  "id: toggle-flag",
  "evidence:",
  "  - id: 1",
  "    kind: source",
  "    target: src/app.lua#L1-L2",
  "```",
  "",
  "Source: `src/app.lua#L1-L2`",
  "",
  "The flag changes here.",
}, walkthrough)

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
  "version: 2",
  "diff: ./change.diff",
  "---",
  "",
  "<!-- code-reader: front-page -->",
  "# Diff overview",
  "",
  "Review the patch.",
  "",
  "---",
  "# 1. Toggle flag",
  "",
  "```code-reader",
  "kind: stage",
  "id: toggle-flag",
  "evidence:",
  "  - id: 1",
  "    kind: diff",
  "    target: src/app.lua#H1",
  "```",
  "",
  "Diff: `src/app.lua#H1`",
  "",
  "The flag changes.",
}, diff_walkthrough)

local code_reader = require("code_reader")
vim.cmd("edit " .. vim.fn.fnameescape(source_file))
vim.cmd("CodeReaderOpen " .. vim.fn.fnameescape(walkthrough))
local state = code_reader.state()
code_reader.next()

vim.api.nvim_set_current_win(state.windows.code)
write_comment(1, 2, { "Keep the flag transition close to its consumer." })
eq(vim.fn.filereadable(review_file), 1, "source review file exists")
local entries = read_entries(review_file)
eq(#entries, 1, "one source review entry")
eq(entries[1].version, 1, "source review version")
eq(entries[1].walkthrough, ".code_reader/flow.md", "source walkthrough path")
eq(entries[1].stage_id, "toggle-flag", "source stage id")
eq(entries[1].evidence_id, 1, "source evidence id")
eq(entries[1].kind, "source", "source review kind")
eq(entries[1].reference, "src/app.lua#L1-L2", "source review reference")
eq(entries[1].comment, "Keep the flag transition close to its consumer.", "source review text")
eq(type(entries[1].created_at), "string", "source review timestamp")

vim.api.nvim_set_current_win(state.windows.explanation)
local explanation_buffer = vim.api.nvim_get_current_buf()
vim.cmd("1,1CodeReaderAddComment")
eq(vim.api.nvim_get_current_buf(), explanation_buffer, "explanation panel does not open comment input")
eq(#read_entries(review_file), 1, "unsupported panel does not write a review")

vim.api.nvim_set_current_win(state.windows.code)
vim.cmd("1,1CodeReaderAddComment")
local empty_buffer = vim.api.nvim_get_current_buf()
vim.cmd("wq")
eq(vim.api.nvim_buf_is_valid(empty_buffer), false, "empty comment buffer closes")
eq(#read_entries(review_file), 1, "empty comment does not write a review")

vim.cmd("1,1CodeReaderAddComment")
local discarded_buffer = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(discarded_buffer, 0, -1, false, { "This comment should not be saved." })
vim.cmd("q!")
eq(vim.api.nvim_buf_is_valid(discarded_buffer), false, "discarded comment buffer closes")
eq(#read_entries(review_file), 1, "discarded comment does not write a review")

vim.cmd("CodeReaderClose")
vim.cmd("edit " .. vim.fn.fnameescape(source_file))
vim.cmd("CodeReaderOpen " .. vim.fn.fnameescape(diff_walkthrough))
state = code_reader.state()
code_reader.next()
local after_buffer = state.buffers.diff_after
local added_line = line_with(after_buffer, "local mode = \"fast\"")
vim.api.nvim_set_current_win(state.windows.diff_after)
write_comment(added_line, added_line, { "Explain why fast mode is safe for this path." })
eq(vim.fn.filereadable(diff_review_file), 1, "diff review file exists")
entries = read_entries(diff_review_file)
eq(#entries, 1, "one diff review entry")
eq(entries[1].kind, "diff", "diff review kind")
eq(entries[1].reference, "src/app.lua#H1@new:L3", "diff review reference")
eq(entries[1].comment, "Explain why fast mode is safe for this path.", "diff review text")

vim.cmd("CodeReaderClose")

print("review_spec: ok")
