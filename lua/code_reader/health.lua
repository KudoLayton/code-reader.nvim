local M = {}

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

function M.inspect(opts)
  opts = opts or {}
  local root = opts.root or plugin_root()
  local mermaid_options = opts.mermaid or {}
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
