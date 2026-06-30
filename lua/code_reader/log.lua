local M = {}

local function default_log_file()
  return vim.fn.stdpath("log") .. "/code-reader.log"
end

local function format_value(value)
  if type(value) == "table" then
    return vim.inspect(value):gsub("%s+", " ")
  end
  return tostring(value)
end

local function sorted_keys(fields)
  local keys = {}
  for key in pairs(fields or {}) do
    table.insert(keys, key)
  end
  table.sort(keys)
  return keys
end

function M.path(options)
  options = options or {}
  local debug_options = options.debug or {}
  return debug_options.log_file or default_log_file()
end

function M.enabled(options)
  options = options or {}
  return options.debug and options.debug.enabled == true
end

function M.write(options, event, fields)
  if not M.enabled(options) then
    return false
  end

  local log_file = M.path(options)
  local parts = {
    os.date("!%Y-%m-%dT%H:%M:%SZ"),
    event,
  }

  for _, key in ipairs(sorted_keys(fields)) do
    local value = fields[key]
    table.insert(parts, key .. "=" .. format_value(value))
  end

  pcall(vim.fn.mkdir, vim.fn.fnamemodify(log_file, ":h"), "p")
  local ok = pcall(vim.fn.writefile, { table.concat(parts, " ") }, log_file, "a")
  return ok
end

return M
