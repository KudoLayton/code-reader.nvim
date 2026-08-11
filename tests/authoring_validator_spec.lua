local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)), 2)
  end
end

local function truthy(value, label)
  if not value then
    error(label, 2)
  end
end

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/src", "p")
vim.fn.writefile({
  "local function simple(value)",
  "  return value + 1",
  "end",
}, tmp .. "/src/app.lua")
vim.fn.writefile({
  "local function complex(value)",
  "  local total = 0",
  "  if value == 0 then total = total + 1 end",
  "  if value == 1 then total = total + 1 end",
  "  if value == 2 then total = total + 1 end",
  "  if value == 3 then total = total + 1 end",
  "  if value == 4 then total = total + 1 end",
  "  if value == 5 then total = total + 1 end",
  "  if value == 6 then total = total + 1 end",
  "  if value == 7 then total = total + 1 end",
  "  if value == 8 then total = total + 1 end",
  "  if value == 9 then total = total + 1 end",
  "  if value == 10 then total = total + 1 end",
  "  return total",
  "end",
}, tmp .. "/src/complex.lua")

local validator = vim.fn.getcwd() .. "/plugins/code-reader-authoring/scripts/validate_code_reader_markdown.py"
local python = vim.fn.exepath("python")
eq(python ~= "", true, "python is available")

local function write_lines(path, lines)
  vim.fn.writefile(lines, path)
end

local function source_document(page_lines)
  local lines = {
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
  }
  vim.list_extend(lines, page_lines)
  return lines
end

local function diff_document(page_lines)
  local lines = {
    "---",
    "type: code-reader-diff",
    "version: 1",
    "diff: ./change.diff",
    "---",
    "",
    "<!-- code-reader: front-page -->",
    "# Overview",
    "",
    "Explain the change.",
    "",
    "---",
    "# 1. Explain change",
    "",
  }
  vim.list_extend(lines, page_lines)
  return lines
end

local function run_validator(path, extra_args)
  local command = { python, validator, "--project-root", tmp }
  vim.list_extend(command, extra_args or {})
  table.insert(command, path)
  local output = vim.fn.system(command)
  return vim.v.shell_error, output
end

local valid_path = tmp .. "/valid.md"
write_lines(valid_path, source_document({
  "Source: `src/app.lua#L1-L3`",
  "Cursor: `src/app.lua#L2`",
  "",
  "Explain the selected function.",
  "",
  "## Invariant",
  "",
  "The result is always the input plus one.",
}))
local valid_status = run_validator(valid_path)
eq(valid_status, 0, "validator accepts one Source reference in the preamble and conceptual child heading")

local invalid_path = tmp .. "/invalid.md"
write_lines(invalid_path, source_document({
  "Source: `src/app.lua#L1-L3`",
  "Cursor: `src/app.lua#L4`",
  "",
  "Explain the selected lines.",
}))
local invalid_status = run_validator(invalid_path)
eq(invalid_status ~= 0, true, "validator rejects cursor outside source range")

local duplicate_source_path = tmp .. "/duplicate-source.md"
write_lines(duplicate_source_path, source_document({
  "Source: `src/app.lua#L1-L3`",
  "Source: `src/app.lua#L1-L2`",
  "",
  "The second Source directive must be a separate page.",
}))
local duplicate_source_status = run_validator(duplicate_source_path)
eq(duplicate_source_status ~= 0, true, "validator rejects multiple Source directives in one page preamble")

local body_source_path = tmp .. "/body-source.md"
write_lines(body_source_path, source_document({
  "Source: `src/app.lua#L1-L3`",
  "",
  "Explain the selected function.",
  "",
  "Source: `src/app.lua#L1-L2`",
}))
local body_source_status = run_validator(body_source_path)
eq(body_source_status ~= 0, true, "validator rejects Source directives outside the page preamble")

local numeric_child_path = tmp .. "/numeric-child.md"
write_lines(numeric_child_path, source_document({
  "Source: `src/app.lua#L1-L3`",
  "",
  "Explain the selected function.",
  "",
  "## 1.1 Nested implementation",
  "",
  "A numbered child heading must start a new page.",
}))
local numeric_child_status = run_validator(numeric_child_path)
eq(numeric_child_status ~= 0, true, "validator rejects numeric child headings in a page")

vim.fn.writefile({
  "diff --git a/src/app.lua b/src/app.lua",
  "--- a/src/app.lua",
  "+++ b/src/app.lua",
  "@@ -1,3 +1,3 @@",
  "-local function simple(value)",
  "+local function simple(input)",
  "   return value + 1",
  " end",
  "@@ -3 +3 @@",
  "-end",
  "+end -- simple",
}, tmp .. "/change.diff")

local valid_diff_path = tmp .. "/valid-diff.md"
write_lines(valid_diff_path, diff_document({
  "Diff: `src/app.lua#H1@new:L1-L3`",
  "Diff: `src/app.lua#H2@new:L3`",
  "",
  "Explain two hunks in the same page metadata preamble.",
}))
local valid_diff_status = run_validator(valid_diff_path)
eq(valid_diff_status, 0, "validator allows multiple Diff directives in a page preamble")

local body_diff_path = tmp .. "/body-diff.md"
write_lines(body_diff_path, diff_document({
  "Diff: `src/app.lua#H1@new:L1-L3`",
  "",
  "Explain the signature change.",
  "",
  "Diff: `src/app.lua#H2@new:L3`",
}))
local body_diff_status = run_validator(body_diff_path)
eq(body_diff_status ~= 0, true, "validator rejects Diff directives outside the page preamble")

vim.fn.writefile({
  "diff --git a/src/app.lua b/src/app.lua",
  "--- a/src/app.lua",
  "+++ b/src/app.lua",
  "@@ -1,3 +1,3 @@",
  " local function simple(value)",
  "-  return value + 0",
  "+  return value + 1",
  " end",
}, tmp .. "/resolved-change.diff")
local resolved_diff_path = tmp .. "/resolved-diff.md"
local resolved_diff_lines = diff_document({
  "Diff: `src/app.lua#H1@new:L1-L3`",
  "",
  "Explain the resolved hunk.",
})
resolved_diff_lines[4] = "diff: ./resolved-change.diff"
write_lines(resolved_diff_path, resolved_diff_lines)
local resolved_inventory_path = tmp .. "/resolved-page-inventory.json"
local resolved_diff_status = run_validator(resolved_diff_path, { "--emit-page-inventory", resolved_inventory_path })
eq(resolved_diff_status, 0, "validator resolves a Diff hunk against matching new-side source")
local resolved_inventory = vim.fn.json_decode(table.concat(vim.fn.readfile(resolved_inventory_path), "\n"))
eq(resolved_inventory.pages[1].diff_resolutions[1].status, "resolved", "inventory records resolved Diff source")
eq(resolved_inventory.pages[1].static_metrics.status, "SUPPORTED", "resolved Diff uses source static metrics")

local complex_path = tmp .. "/complex.md"
write_lines(complex_path, source_document({
  "Source: `src/complex.lua#L1-L15`",
  "",
  "Explain the complex function.",
}))
local inventory_path = tmp .. "/page-inventory.json"
local complex_status = run_validator(complex_path, { "--emit-page-inventory", inventory_path })
eq(complex_status ~= 0, true, "validator blocks a page whose static complexity requires a split")
truthy(vim.fn.filereadable(inventory_path) == 1, "validator writes page inventory when static split is required")
local inventory = vim.fn.json_decode(table.concat(vim.fn.readfile(inventory_path), "\n"))
eq(inventory.schema, "code-reader-page-inventory/v1", "inventory schema")
eq(#inventory.pages, 1, "inventory contains the complex page")
local complex_page = inventory.pages[1]
eq(complex_page.static_verdict, "SPLIT_REQUIRED", "high V(G) page requires a split")
eq(complex_page.static_metrics.status, "SUPPORTED", "Lua static metrics are available")
eq(complex_page.static_metrics.cyclomatic_complexity, 12, "static V(G) counts eleven Lua if decisions")
truthy(type(complex_page.static_metrics.peak_live_bindings) == "number", "inventory records peak live bindings")
truthy(type(complex_page.static_metrics.analysis_region) == "table", "inventory records static analysis region")
truthy(type(complex_page.static_metrics.evidence) == "table", "inventory records metric evidence")

print("authoring_validator_spec: ok")
