vim.opt.runtimepath:append(vim.fn.getcwd())

package.path = table.concat({
  "lua/?.lua",
  "lua/?/init.lua",
  package.path,
}, ";")

local parser = require("code_reader.parser")
local links = require("code_reader.links")
local diff = require("code_reader.diff")

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
local diff_explanation_path = demo_root .. "/.code_reader/diffs/request-update.md"
local diff_path = demo_root .. "/.code_reader/diffs/request-update.diff"

local lines = vim.fn.readfile(explanation_path)
local doc = parser.parse(table.concat(lines, "\n"), { path = explanation_path })

eq(doc.frontmatter.type, "code-reader", "frontmatter type")
eq(#doc.steps, 6, "demo step count")
eq(doc.front_page_index, 1, "demo front page index")
eq(doc.steps[1].kind, "front_page", "demo front page kind")
eq(#doc.steps[1].sources, 0, "demo front page source count")

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
  if step.kind ~= "front_page" then
    ok(#step.sources > 0, "step has source: " .. step.id)
    for _, source_ref in ipairs(step.sources) do
      local path = demo_root .. "/" .. source_ref.path
      eq(vim.fn.filereadable(path), 1, "source exists: " .. source_ref.path)
      local source_lines = vim.fn.readfile(path)
      ok(source_ref.start_line >= 1, "source range starts after first line: " .. source_ref.path)
      ok(source_ref.end_line <= #source_lines, "source range ends inside file: " .. source_ref.path)
    end
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

local diff_lines = vim.fn.readfile(diff_explanation_path)
local diff_doc = parser.parse(table.concat(diff_lines, "\n"), { path = diff_explanation_path })
local parsed_diff = diff.parse(table.concat(vim.fn.readfile(diff_path), "\n"))

eq(diff_doc.frontmatter.type, "code-reader-diff", "diff demo frontmatter type")
eq(diff_doc.frontmatter.diff, "./request-update.diff", "diff demo diff path")
eq(#diff_doc.steps, 5, "diff demo step count")
eq(diff_doc.front_page_index, 1, "diff demo front page index")
eq(#parsed_diff.files, 3, "diff demo file count")
eq(parsed_diff.total_changed_lines, 9, "diff demo changed line count")

for _, step in ipairs(diff_doc.steps) do
  if step.kind ~= "front_page" then
    ok(#step.diff_refs > 0, "diff demo step has diff ref: " .. step.id)
    for _, diff_ref in ipairs(step.diff_refs) do
      local file = parsed_diff.file_by_path[diff_ref.path]
      ok(file, "diff demo file exists in diff: " .. diff_ref.path)
      ok(file.hunk_by_id[diff_ref.hunk_id], "diff demo hunk exists: " .. diff_ref.path .. "#" .. diff_ref.hunk_id)
      eq(vim.fn.filereadable(demo_root .. "/" .. diff_ref.path), 1, "diff demo source exists: " .. diff_ref.path)
    end
  end
end

print("demo_spec: ok")
