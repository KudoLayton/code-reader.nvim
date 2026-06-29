local M = {}

local uv = vim.uv or vim.loop

local function is_absolute(path)
  return path:match("^/") or path:match("^%a:[/\\]")
end

local function join_path(root, path)
  if is_absolute(path) then
    return path
  end
  return (root:gsub("[/\\]$", "")) .. "/" .. path
end

local function mtime_seconds(stat)
  if not stat or not stat.mtime then
    return nil
  end
  return stat.mtime.sec + (stat.mtime.nsec or 0) / 1000000000
end

function M.resolve_path(source_ref, opts)
  opts = opts or {}
  local root = opts.root or uv.cwd()
  return vim.fn.fnamemodify(join_path(root, source_ref.path), ":p")
end

function M.range_hash(path, start_line, end_line)
  start_line = tonumber(start_line)
  end_line = tonumber(end_line) or start_line

  if not start_line or start_line < 1 or end_line < start_line then
    return nil, "invalid-range"
  end

  local ok, lines = pcall(vim.fn.readfile, path, "", end_line)
  if not ok then
    return nil, "read-failed"
  end

  if #lines < end_line then
    return nil, "range-out-of-bounds"
  end

  local selected = {}
  for index = start_line, end_line do
    table.insert(selected, lines[index])
  end

  return vim.fn.sha256(table.concat(selected, "\n"))
end

function M.status(source_ref, opts)
  opts = opts or {}
  local path = M.resolve_path(source_ref, opts)
  local stat = uv.fs_stat(path)
  if not stat then
    return {
      kind = "missing",
      path = path,
      message = "source file is missing",
    }
  end

  local hash, hash_error = M.range_hash(path, source_ref.start_line, source_ref.end_line)
  if not hash then
    return {
      kind = "stale",
      path = path,
      reason = hash_error,
      message = "source range cannot be read",
    }
  end

  if source_ref.expected_hash then
    local expected = source_ref.expected_hash:lower()
    if hash:lower() ~= expected then
      return {
        kind = "stale",
        path = path,
        current_hash = hash,
        expected_hash = expected,
        message = "source hash changed",
      }
    end
  elseif opts.explanation_path then
    local explanation_stat = uv.fs_stat(opts.explanation_path)
    if mtime_seconds(stat) and mtime_seconds(explanation_stat) and mtime_seconds(stat) > mtime_seconds(explanation_stat) then
      return {
        kind = "stale",
        path = path,
        current_hash = hash,
        message = "source file is newer than explanation",
      }
    end
  end

  return {
    kind = "fresh",
    path = path,
    current_hash = hash,
    message = "source is current",
  }
end

function M.status_label(status)
  if not status then
    return "unknown"
  end
  if status.kind == "fresh" then
    return "fresh"
  end
  if status.kind == "stale" then
    return "stale: " .. (status.message or status.reason or "changed")
  end
  if status.kind == "missing" then
    return "missing"
  end
  return status.kind
end

return M
