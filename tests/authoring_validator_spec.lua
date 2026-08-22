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

local function document(target, link)
  return {
    "---", "type: code-reader", "version: 2", "feature: validator-test", "---",
    "# Overview", "```code-reader", "kind: overview", "id: validator-test",
    "question: What does the selected function do?", "state:", "  status: not_applicable",
    "  reason: Overview is descriptive.", "responsibility:", "  status: applicable", "  items:",
    "    - owner: selected function", "      action: Perform the feature work", "```",
    "---", "# 1. Explain source", "```code-reader", "kind: stage", "id: explain-source",
    "question: What is the function responsibility?", "trigger: The feature calls the function", "state:",
    "  status: applicable", "  changes:", "    - subject: result", "      owner: selected function",
    "      before: input", "      cause: function returns", "      after: result", "      invariant: result follows the function contract",
    "responsibility:", "  status: applicable", "  items:", "    - owner: selected function", "      action: Produce the result",
    "failure:", "  status: not_applicable", "  reason: The selected example has no failure branch.", "evidence:",
    "  - id: 1", "    kind: source", "    target: " .. target, "    claim: The selected function implements the result transition.", "```",
    "The implementation evidence is " .. (link or "[1](code-reader://evidence/1)") .. ".",
  }
end

local function run_validator(path, extra_args)
  local command = { python, validator, "--project-root", tmp }
  vim.list_extend(command, extra_args or {})
  table.insert(command, path)
  local output = vim.fn.system(command)
  return vim.v.shell_error, output
end

local valid_path = tmp .. "/valid.md"
vim.fn.writefile(document("src/app.lua#L1-L3"), valid_path)
local valid_status = run_validator(valid_path)
eq(valid_status, 0, "validator accepts a v2 source stage")

local invalid_path = tmp .. "/invalid.md"
vim.fn.writefile(document("src/app.lua#L1-L3", "[2](code-reader://evidence/2)"), invalid_path)
local invalid_status = run_validator(invalid_path)
eq(invalid_status ~= 0, true, "validator rejects an unknown evidence link")

local complex_path = tmp .. "/complex.md"
vim.fn.writefile(document("src/complex.lua#L1-L15"), complex_path)
local inventory_path = tmp .. "/page-inventory.json"
local complex_status = run_validator(complex_path, { "--emit-page-inventory", inventory_path })
eq(complex_status ~= 0, true, "validator blocks a v2 evidence range whose complexity requires a split")
truthy(vim.fn.filereadable(inventory_path) == 1, "validator writes a v2 page inventory")
local inventory = vim.fn.json_decode(table.concat(vim.fn.readfile(inventory_path), "\n"))
eq(inventory.schema, "code-reader-page-inventory/v2", "v2 inventory schema")
eq(#inventory.pages, 2, "inventory contains overview and stage")
local evidence = inventory.pages[2].evidence[1]
eq(evidence.static_verdict, "SPLIT_REQUIRED", "high V(G) evidence requires a split")
eq(evidence.static_metrics.cyclomatic_complexity, 12, "static V(G) counts eleven Lua if decisions")

print("authoring_validator_spec: ok")
