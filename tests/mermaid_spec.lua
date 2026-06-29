package.path = table.concat({
  "lua/?.lua",
  "lua/?/init.lua",
  package.path,
}, ";")

local mermaid = require("code_reader.mermaid")

local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)), 2)
  end
end

local function contains(lines, needle)
  local joined = table.concat(lines, "\n")
  return joined:find(needle, 1, true) ~= nil
end

local fake_success = {
  "lua",
  "-e",
  "io.read('*a'); print('A --> B')",
}

local fake_failure = {
  "lua",
  "-e",
  "io.stderr:write('nope'); os.exit(1)",
}

local sample = {
  "Before",
  "``` mermaid",
  "flowchart TD",
  "  A --> B",
  "```",
  "After",
}

local disabled = mermaid.render_lines(sample, {
  enabled = false,
  command = fake_success,
})
eq(table.concat(disabled, "\n"), table.concat(sample, "\n"), "disabled keeps original")

local rendered = mermaid.render_lines(sample, {
  enabled = true,
  command = fake_success,
})
eq(contains(rendered, "A --> B"), true, "rendered output included")
eq(contains(rendered, "``` mermaid"), false, "rendered fence removed")
eq(contains(rendered, "Before"), true, "content before block kept")
eq(contains(rendered, "After"), true, "content after block kept")

local failed = mermaid.render_lines(sample, {
  enabled = true,
  command = fake_failure,
})
eq(table.concat(failed, "\n"), table.concat(sample, "\n"), "failure keeps original")

local regular_code = {
  "```lua",
  "print('hello')",
  "```",
}
local regular_result = mermaid.render_lines(regular_code, {
  enabled = true,
  command = fake_success,
})
eq(table.concat(regular_result, "\n"), table.concat(regular_code, "\n"), "non-mermaid code kept")

print("mermaid_spec: ok")
