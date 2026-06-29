local M = {}

local uv = vim.uv or vim.loop

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function split_lines(text)
  local lines = {}
  text = text or ""
  if text == "" then
    return lines
  end

  text = text:gsub("\r\n", "\n"):gsub("\r", "\n") .. "\n"
  for line in text:gmatch("(.-)\n") do
    table.insert(lines, line)
  end
  return lines
end

local function script_path()
  local source = debug.getinfo(1, "S").source:gsub("^@", "")
  local root = vim.fn.fnamemodify(source, ":p:h:h:h")
  return root .. "/scripts/code-reader-mermaid.mjs"
end

local function default_command()
  return { "node", script_path() }
end

local function normalize_command(opts)
  local command = opts.command
  if type(command) == "table" then
    return command
  end
  if type(command) == "string" and command ~= "" then
    return { command }
  end

  command = default_command()
  if opts.use_ascii then
    table.insert(command, "--ascii")
  end
  return command
end

local function run_command(command, input, timeout_ms)
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  local stdin = uv.new_pipe(false)
  local output = {}
  local errors = {}
  local done = false
  local timed_out = false
  local exit_code = nil

  local timer = uv.new_timer()
  local handle
  handle = uv.spawn(command[1], {
    args = vim.list_slice(command, 2),
    stdio = { stdin, stdout, stderr },
  }, function(code)
    exit_code = code
    done = true
    if timer then
      timer:stop()
      timer:close()
    end
  end)

  if not handle then
    stdout:close()
    stderr:close()
    stdin:close()
    timer:close()
    return nil, "spawn-failed"
  end

  stdout:read_start(function(_, data)
    if data then
      table.insert(output, data)
    end
  end)
  stderr:read_start(function(_, data)
    if data then
      table.insert(errors, data)
    end
  end)

  stdin:write(input)
  stdin:shutdown(function()
    stdin:close()
  end)

  timer:start(timeout_ms or 2000, 0, function()
    timed_out = true
    done = true
    handle:kill("sigterm")
  end)

  vim.wait((timeout_ms or 2000) + 100, function()
    return done
  end, 10)

  stdout:read_stop()
  stderr:read_stop()
  stdout:close()
  stderr:close()
  if not handle:is_closing() then
    handle:close()
  end

  if timed_out then
    return nil, "timeout"
  end
  if exit_code ~= 0 then
    local message = trim(table.concat(errors))
    return nil, message ~= "" and message or "render-failed"
  end

  return table.concat(output)
end

local function is_mermaid_fence(line)
  local info = line:match("^%s*```%s*(.-)%s*$")
  if not info then
    return false
  end
  local language = info:match("^(%S+)") or ""
  return language:lower() == "mermaid"
end

local function is_closing_fence(line)
  return line:match("^%s*```%s*$") ~= nil
end

local function render_block(block, opts)
  local command = normalize_command(opts)
  local output = run_command(command, table.concat(block, "\n"), opts.timeout_ms)
  if not output or trim(output) == "" then
    return nil
  end
  return split_lines(output:gsub("%s+$", ""))
end

function M.render_lines(lines, opts)
  opts = opts or {}
  if opts.enabled == false then
    return lines
  end

  local result = {}
  local index = 1

  while index <= #lines do
    local line = lines[index]
    if is_mermaid_fence(line) then
      local block = {}
      local close_index = nil
      local cursor = index + 1

      while cursor <= #lines do
        if is_closing_fence(lines[cursor]) then
          close_index = cursor
          break
        end
        table.insert(block, lines[cursor])
        cursor = cursor + 1
      end

      if close_index then
        local rendered = render_block(block, opts)
        if rendered then
          for _, rendered_line in ipairs(rendered) do
            table.insert(result, rendered_line)
          end
        else
          for copy_index = index, close_index do
            table.insert(result, lines[copy_index])
          end
        end
        index = close_index + 1
      else
        table.insert(result, line)
        index = index + 1
      end
    else
      table.insert(result, line)
      index = index + 1
    end
  end

  return result
end

function M.default_command()
  return default_command()
end

return M
