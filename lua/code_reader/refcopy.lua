local M = {}

local function normalize_path(path)
  return (path or ""):gsub("\\", "/")
end

local function relative_path(path, root)
  path = normalize_path(vim.fn.fnamemodify(path, ":p"))
  root = normalize_path(vim.fn.fnamemodify(root or vim.fn.getcwd(), ":p")):gsub("/$", "")
  if path:sub(1, #root + 1) == root .. "/" then
    return path:sub(#root + 2)
  end
  return normalize_path(vim.fn.fnamemodify(path, ":."))
end

local function range_ref(path, start_line, end_line)
  if start_line == end_line then
    return string.format("%s#L%d", path, start_line)
  end
  return string.format("%s#L%d-L%d", path, start_line, end_line)
end

local function selected_lines(bufnr, line1, line2)
  local start_line = math.min(line1, line2)
  local end_line = math.max(line1, line2)
  return vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false), start_line, end_line
end

local function selection_text(bufnr, line1, line2)
  local lines = selected_lines(bufnr, line1, line2)
  return table.concat(lines, "\n")
end

local function copy_text(text, register)
  vim.fn.setreg(register or "+", text)
end

local function markdown_ref(state, map, bufnr, line1, line2)
  local _, start_line, end_line = selected_lines(bufnr, line1, line2)
  local min_line = nil
  local max_line = nil
  local has_markdown = false

  for line = start_line, end_line do
    local item = map[line]
    local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
    if item and item.kind == "markdown" and item.start_line and item.end_line then
      has_markdown = true
      min_line = math.min(min_line or item.start_line, item.start_line)
      max_line = math.max(max_line or item.end_line, item.end_line)
    elseif text:match("%S") then
      return nil
    end
  end

  if not has_markdown then
    return nil
  end
  return range_ref(relative_path(state.path, state.root), min_line, max_line)
end

local function same_diff_target(target, item)
  return target.path == item.path and target.side == item.side and target.hunk == item.hunk
end

local function hunk_range(item)
  if not item.hunk then
    return nil, nil
  end
  if item.side == "old" then
    return item.hunk.old_start, item.hunk.old_end
  end
  return item.hunk.new_start, item.hunk.new_end
end

local function diff_ref(map, bufnr, line1, line2)
  local _, start_line, end_line = selected_lines(bufnr, line1, line2)
  local target = nil
  local min_line = nil
  local max_line = nil

  for line = start_line, end_line do
    local item = map[line]
    local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
    if item and item.kind == "diff" and item.hunk then
      target = target or item
      if not same_diff_target(target, item) then
        return nil
      end
      if item.line_no then
        min_line = math.min(min_line or item.line_no, item.line_no)
        max_line = math.max(max_line or item.line_no, item.line_no)
      elseif text:match("%S") then
        local fallback_start, fallback_end = hunk_range(item)
        min_line = math.min(min_line or fallback_start, fallback_start)
        max_line = math.max(max_line or fallback_end, fallback_end)
      end
    elseif text:match("%S") then
      return nil
    end
  end

  if not target then
    return nil
  end
  if not (min_line and max_line) then
    min_line, max_line = hunk_range(target)
  end
  if not (min_line and max_line) then
    return string.format("%s#%s@%s", target.path, target.hunk.id, target.side)
  end
  local suffix = min_line == max_line and ("L" .. tostring(min_line)) or ("L" .. tostring(min_line) .. "-L" .. tostring(max_line))
  return string.format("%s#%s@%s:%s", target.path, target.hunk.id, target.side, suffix)
end

local function mapped_ref(state, map, bufnr, line1, line2)
  local first = map[math.min(line1, line2)]
  if first and first.kind == "diff" then
    return diff_ref(map, bufnr, line1, line2)
  end
  return markdown_ref(state, map, bufnr, line1, line2)
end

local function file_ref(state, bufnr, line1, line2)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return nil
  end
  return range_ref(relative_path(name, state and state.root or nil), math.min(line1, line2), math.max(line1, line2))
end

function M.copy(state, opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local line1 = opts.line1 or vim.fn.line(".")
  local line2 = opts.line2 or line1
  local map = state and state.refcopy_maps and state.refcopy_maps[bufnr] or nil
  local text = nil

  if map then
    text = mapped_ref(state, map, bufnr, line1, line2) or selection_text(bufnr, line1, line2)
  else
    text = file_ref(state, bufnr, line1, line2) or selection_text(bufnr, line1, line2)
  end

  copy_text(text, opts.register or opts.clipboard_register or "+")
  if opts.notify ~= false then
    vim.notify("Code Reader: copied reference", vim.log.levels.INFO)
  end
  return true
end

return M
