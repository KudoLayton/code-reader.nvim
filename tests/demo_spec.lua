vim.opt.runtimepath:append(vim.fn.getcwd())

package.path = table.concat({
  "lua/?.lua",
  "lua/?/init.lua",
  package.path,
}, ";")

local parser = require("code_reader.parser")
local links = require("code_reader.links")

local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)), 2)
  end
end

local function ok(value, label)
  if not value then
    error(label, 2)
  end
end

local root = vim.fn.getcwd()
local demo_root = root .. "/demo/basic"
local explanation_path = demo_root .. "/.code_reader/walkthrough.md"

local lines = vim.fn.readfile(explanation_path)
local doc = parser.parse(table.concat(lines, "\n"), { path = explanation_path })

eq(doc.frontmatter.type, "code-reader", "frontmatter type")
eq(#doc.steps, 5, "demo step count")

local forbidden_dirs = {
  "plugin",
  "ftplugin",
  "after",
  "lua",
}

for _, name in ipairs(forbidden_dirs) do
  eq(vim.fn.isdirectory(demo_root .. "/" .. name), 0, "forbidden demo directory: " .. name)
end

local forbidden_files = {
  ".nvim.lua",
  ".exrc",
  "init.lua",
}

for _, name in ipairs(forbidden_files) do
  eq(vim.fn.filereadable(demo_root .. "/" .. name), 0, "forbidden demo config: " .. name)
end

for _, step in ipairs(doc.steps) do
  ok(#step.sources > 0, "step has source: " .. step.id)
  for _, source_ref in ipairs(step.sources) do
    local path = demo_root .. "/" .. source_ref.path
    eq(vim.fn.filereadable(path), 1, "source exists: " .. source_ref.path)
    local source_lines = vim.fn.readfile(path)
    ok(source_ref.start_line >= 1, "source range starts after first line: " .. source_ref.path)
    ok(source_ref.end_line <= #source_lines, "source range ends inside file: " .. source_ref.path)
  end
end

for line_number, line in ipairs(lines) do
  local search_from = 1
  while true do
    local start_index = line:find("[[", search_from, true)
    if not start_index then
      break
    end

    local link = links.find_at(line, start_index + 1)
    ok(link and link.kind == "step", "internal link parsed at line " .. line_number)
    ok(doc.step_by_id[link.target], "internal link target exists: " .. link.target)
    search_from = start_index + 2
  end

  search_from = 1
  while true do
    local start_index = line:find("treesitter://", search_from, true)
    if not start_index then
      break
    end

    local link = links.find_at(line, start_index)
    ok(link and link.kind == "treesitter", "treesitter link parsed at line " .. line_number)
    ok(link.path:match("^src/"), "treesitter link uses demo source path: " .. link.path)
    ok(link.query and link.query ~= "", "treesitter link has query at line " .. line_number)
    eq(vim.fn.filereadable(demo_root .. "/" .. link.path), 1, "treesitter source exists: " .. link.path)
    search_from = start_index + 1
  end
end

print("demo_spec: ok")
