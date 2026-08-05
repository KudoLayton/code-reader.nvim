local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)), 2)
  end
end

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/src", "p")
vim.fn.writefile({ "first", "second", "third" }, tmp .. "/src/app.lua")

local validator = vim.fn.getcwd() .. "/plugins/code-reader-authoring/scripts/validate_code_reader_markdown.py"
local python = vim.fn.exepath("python")
eq(python ~= "", true, "python is available")

local function write_document(path, cursor_line)
  vim.fn.writefile({
    "---",
    "type: code-reader",
    "version: 1",
    "---",
    "",
    "<!-- code-reader: front-page -->",
    "# Overview",
    "",
    "Explain the problem and expected outcome.",
    "",
    "---",
    "# 1. Explain source",
    "",
    "Source: `src/app.lua#L1-L2`",
    "Cursor: `src/app.lua#L" .. tostring(cursor_line) .. "`",
    "",
    "Explain the selected lines.",
  }, path)
end

local valid_path = tmp .. "/valid.md"
write_document(valid_path, 2)
vim.fn.system({ python, validator, "--project-root", tmp, valid_path })
eq(vim.v.shell_error, 0, "validator accepts cursor inside source range")

local invalid_path = tmp .. "/invalid.md"
write_document(invalid_path, 3)
vim.fn.system({ python, validator, "--project-root", tmp, invalid_path })
eq(vim.v.shell_error ~= 0, true, "validator rejects cursor outside source range")

print("authoring_validator_spec: ok")
