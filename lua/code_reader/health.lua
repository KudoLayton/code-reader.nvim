local M = {}
local log = require("code_reader.log")
local syntax = require("code_reader.syntax")

local function plugin_root()
  local source = debug.getinfo(1, "S").source:gsub("^@", "")
  return vim.fn.fnamemodify(source, ":p:h:h:h")
end

local function helper_path(root)
  return root .. "/scripts/code-reader-mermaid.mjs"
end

local function dependency_path(root)
  return root .. "/node_modules/beautiful-mermaid"
end

local function run_version(env, executable)
  local output, exit_code = env.system({ executable, "--version" })
  if exit_code ~= 0 then
    return nil
  end
  return (output or ""):gsub("%s+$", "")
end

local function smoke_helper(env, root)
  local input = "flowchart TD\n  A --> B\n"
  local output, exit_code = env.system({ "node", helper_path(root) }, input)
  if exit_code ~= 0 then
    return false, (output or ""):gsub("%s+$", "")
  end
  return true, (output or ""):gsub("%s+$", "")
end

local function default_env()
  return {
    system = function(command, input)
      local output = vim.fn.system(command, input)
      return output, vim.v.shell_error
    end,
    filereadable = vim.fn.filereadable,
    isdirectory = vim.fn.isdirectory,
  }
end

local function add(checks, level, name, message)
  table.insert(checks, {
    level = level,
    name = name,
    message = message,
  })
end

local function unique_sorted(values)
  local seen = {}
  local result = {}
  for _, value in ipairs(values or {}) do
    if value and value ~= "" and not seen[value] then
      seen[value] = true
      table.insert(result, value)
    end
  end
  table.sort(result)
  return result
end

local function inspect_language(checks, filetype, env)
  local result = syntax.inspect_language(filetype, { env = env and env.syntax or nil })
  local name = "treesitter:" .. tostring(filetype)
  if not result.language then
    add(checks, "warn", name, "Tree-sitter language not resolved for filetype " .. tostring(filetype))
    return
  end
  if not result.parser then
    add(checks, "warn", name, "Tree-sitter parser unavailable for " .. result.language .. ": " .. tostring(result.error))
    return
  end
  if not result.query then
    add(checks, "warn", name, "Tree-sitter highlights query unavailable for " .. result.language .. ": " .. tostring(result.error))
    return
  end
  add(checks, "ok", name, "Tree-sitter syntax available for " .. tostring(filetype) .. " (" .. result.language .. ")")
end

local function inspect_path(checks, path, env)
  local result = syntax.inspect_path(path, { env = env and env.syntax or nil })
  local name = "diff-syntax:" .. tostring(path)
  if not result.filetype then
    add(checks, "warn", name, "Cannot infer filetype for diff path: " .. tostring(path))
    return
  end
  if not result.language then
    add(checks, "warn", name, "Tree-sitter language not resolved for diff path " .. tostring(path) .. " (filetype " .. result.filetype .. ")")
    return
  end
  if not result.parser then
    add(checks, "warn", name, "Tree-sitter parser unavailable for diff path " .. tostring(path) .. " (" .. result.language .. "): " .. tostring(result.error))
    return
  end
  if not result.query then
    add(checks, "warn", name, "Tree-sitter highlights query unavailable for diff path " .. tostring(path) .. " (" .. result.language .. "): " .. tostring(result.error))
    return
  end
  add(
    checks,
    "ok",
    name,
    "Tree-sitter diff syntax available for " .. tostring(path) .. " (filetype " .. result.filetype .. ", language " .. result.language .. ")"
  )
end

local function inspect_syntax(checks, opts, env)
  local paths = unique_sorted(opts.syntax_paths or {})
  if #paths > 0 then
    for _, path in ipairs(paths) do
      inspect_path(checks, path, env)
    end
    return
  end

  for _, filetype in ipairs({ "c", "cpp", "lua" }) do
    inspect_language(checks, filetype, env)
  end
end

local function inspect_debug(checks, options)
  if log.enabled(options) then
    add(checks, "ok", "debug", "Debug log enabled: " .. log.path(options))
  else
    add(checks, "info", "debug", "Debug log disabled")
  end
end

function M.inspect(opts)
  opts = opts or {}
  local root = opts.root or plugin_root()
  local mermaid_options = opts.mermaid or {}
  local options = opts.options or {}
  local env = opts.env or default_env()
  local enabled = mermaid_options.enabled ~= false
  local checks = {}

  if not enabled then
    add(checks, "info", "mermaid", "Mermaid rendering is disabled")
  end

  local node_version = run_version(env, "node")
  if node_version then
    add(checks, "ok", "node", "node executable found: " .. node_version)
  else
    add(checks, enabled and "error" or "warn", "node", "node executable not found")
  end

  local npm_version = run_version(env, "npm")
  if npm_version then
    add(checks, "ok", "npm", "npm executable found: " .. npm_version)
  else
    add(checks, enabled and "warn" or "info", "npm", "npm executable not found")
  end

  local helper = helper_path(root)
  if env.filereadable(helper) == 1 then
    add(checks, "ok", "helper", "Mermaid helper found: " .. helper)
  else
    add(checks, enabled and "error" or "warn", "helper", "Mermaid helper not found: " .. helper)
  end

  local dependency = dependency_path(root)
  if env.isdirectory(dependency) == 1 then
    add(checks, "ok", "dependency", "beautiful-mermaid dependency installed")
  else
    add(checks, enabled and "warn" or "info", "dependency", "beautiful-mermaid dependency not installed; run npm install")
  end

  if enabled and node_version and env.filereadable(helper) == 1 and env.isdirectory(dependency) == 1 then
    local ok, output = smoke_helper(env, root)
    if ok and output ~= "" then
      add(checks, "ok", "smoke", "Mermaid helper smoke test passed")
    else
      add(checks, "error", "smoke", "Mermaid helper smoke test failed: " .. (output ~= "" and output or "no output"))
    end
  end

  inspect_syntax(checks, opts, env)
  inspect_debug(checks, options)

  return checks
end

local function health_api()
  local health = vim.health or {}
  return {
    start = health.start or health.report_start,
    ok = health.ok or health.report_ok,
    warn = health.warn or health.report_warn,
    error = health.error or health.report_error,
    info = health.info or health.report_info,
  }
end

function M.check(opts)
  local api = health_api()
  api.start("code-reader.nvim")

  for _, check in ipairs(M.inspect(opts)) do
    local report = api[check.level] or api.info
    report(check.message)
  end
end

return M
