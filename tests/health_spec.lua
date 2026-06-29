vim.opt.runtimepath:append(vim.fn.getcwd())

package.path = table.concat({
  "lua/?.lua",
  "lua/?/init.lua",
  package.path,
}, ";")

local health = require("code_reader.health")

local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)), 2)
  end
end

local function find(checks, name)
  for _, check in ipairs(checks) do
    if check.name == name then
      return check
    end
  end
end

local ok_env = {
  system = function(command)
    if command[1] == "node" and command[2] == "--version" then
      return "v22.0.0\n", 0
    end
    if command[1] == "npm" and command[2] == "--version" then
      return "10.0.0\n", 0
    end
    return "A --> B\n", 0
  end,
  filereadable = function()
    return 1
  end,
  isdirectory = function()
    return 1
  end,
}

local ok_checks = health.inspect({
  root = "D:/Git/code-reader",
  env = ok_env,
})
eq(find(ok_checks, "node").level, "ok", "node ok")
eq(find(ok_checks, "npm").level, "ok", "npm ok")
eq(find(ok_checks, "helper").level, "ok", "helper ok")
eq(find(ok_checks, "dependency").level, "ok", "dependency ok")
eq(find(ok_checks, "smoke").level, "ok", "smoke ok")

local missing_env = {
  system = function()
    return "", 1
  end,
  filereadable = function()
    return 0
  end,
  isdirectory = function()
    return 0
  end,
}

local enabled_missing = health.inspect({
  root = "D:/Git/code-reader",
  env = missing_env,
})
eq(find(enabled_missing, "node").level, "error", "enabled missing node error")
eq(find(enabled_missing, "helper").level, "error", "enabled missing helper error")
eq(find(enabled_missing, "dependency").level, "warn", "enabled missing dependency warn")

local disabled_missing = health.inspect({
  root = "D:/Git/code-reader",
  mermaid = {
    enabled = false,
  },
  env = missing_env,
})
eq(find(disabled_missing, "mermaid").level, "info", "disabled mermaid info")
eq(find(disabled_missing, "node").level, "warn", "disabled missing node warn")
eq(find(disabled_missing, "dependency").level, "info", "disabled missing dependency info")

print("health_spec: ok")
