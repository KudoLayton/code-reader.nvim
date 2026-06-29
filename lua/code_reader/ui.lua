local source = require("code_reader.source")

local M = {}

local namespace = vim.api.nvim_create_namespace("code-reader")

local function set_lines(buf, lines)
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
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

local function create_scratch(name, filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_set_option_value("filetype", filetype, { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  return buf
end

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function source_ref_label(source_ref)
  if not source_ref then
    return "none"
  end

  local suffix = "#L" .. tostring(source_ref.start_line)
  if source_ref.end_line and source_ref.end_line ~= source_ref.start_line then
    suffix = suffix .. "-L" .. tostring(source_ref.end_line)
  end
  return source_ref.path .. suffix
end

local function step_link(step)
  return "[[" .. step.id .. "|" .. step.title .. "]]"
end

local function parent_step(state, step)
  if not step or not step.id then
    return nil
  end

  local parent_id = step.id:match("^(.+)%.%d+$")
  if parent_id and state.doc.step_by_id then
    local parent_index = state.doc.step_by_id[parent_id]
    return parent_index and state.doc.steps[parent_index] or nil
  end

  local target_depth = (step.depth or 1) - 1
  if target_depth < 1 then
    return nil
  end

  for index = step.index - 1, 1, -1 do
    local candidate = state.doc.steps[index]
    if candidate.depth == target_depth then
      return candidate
    end
  end
end

local function child_steps(state, step)
  local children = {}
  local child_depth = (step.depth or 1) + 1

  for index = step.index + 1, #state.doc.steps do
    local candidate = state.doc.steps[index]
    if (candidate.depth or 1) <= (step.depth or 1) then
      break
    end
    if candidate.depth == child_depth then
      table.insert(children, candidate)
    end
  end

  return children
end

local function append_navigation(lines, state, step, source_ref)
  table.insert(lines, "")
  table.insert(lines, "---")
  table.insert(lines, "## Navigation")
  table.insert(lines, "")

  local previous = state.doc.steps[state.current - 1]
  local next_step = state.doc.steps[state.current + 1]
  local parent = parent_step(state, step)
  local children = child_steps(state, step)

  if previous then
    table.insert(lines, "- Previous: " .. step_link(previous))
  end
  if next_step then
    table.insert(lines, "- Next: " .. step_link(next_step))
  end
  if parent then
    table.insert(lines, "- Parent: " .. step_link(parent))
  end
  if #children > 0 then
    table.insert(lines, "- Children:")
    for _, child in ipairs(children) do
      table.insert(lines, "  - " .. step_link(child))
    end
  end

  table.insert(lines, "- Source: `" .. source_ref_label(source_ref) .. "`")
end

function M.setup_highlights()
  vim.api.nvim_set_hl(0, "CodeReaderActiveLine", { bg = "#263238", default = true })
  vim.api.nvim_set_hl(0, "CodeReaderDimLine", { fg = "#6b7280", default = true })
  vim.api.nvim_set_hl(0, "CodeReaderCurrentStep", { fg = "#f8fafc", bg = "#374151", bold = true, default = true })
  vim.api.nvim_set_hl(0, "CodeReaderSymbolText", { bg = "#3f3f46", default = true })
  vim.api.nvim_set_hl(0, "CodeReaderSymbolRead", { bg = "#1e3a5f", default = true })
  vim.api.nvim_set_hl(0, "CodeReaderSymbolWrite", { bg = "#5f3b1e", default = true })
  vim.api.nvim_set_hl(0, "CodeReaderSymbolFallback", { bg = "#334155", default = true })
  vim.api.nvim_set_hl(0, "CodeReaderSymbolSeed", { underline = true, bold = true, default = true })
end

function M.open_layout(state)
  M.setup_highlights()

  state.windows = state.windows or {}
  state.buffers = state.buffers or {}

  state.windows.code = vim.api.nvim_get_current_win()
  state.buffers.explanation = create_scratch("code-reader://explanation", "markdown")
  state.buffers.toc = create_scratch("code-reader://toc", "code_reader_toc")

  vim.cmd("vsplit")
  state.windows.explanation = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.windows.explanation, state.buffers.explanation)
  vim.api.nvim_win_set_width(state.windows.explanation, math.max(46, math.floor(vim.o.columns * 0.38)))

  vim.cmd("belowright split")
  state.windows.toc = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.windows.toc, state.buffers.toc)
  vim.api.nvim_win_set_height(state.windows.toc, math.max(8, math.floor(vim.o.lines * 0.22)))

  vim.api.nvim_set_current_win(state.windows.explanation)
end

function M.render_explanation(state)
  if not valid_buf(state.buffers.explanation) then
    return
  end

  local step = state.doc.steps[state.current]
  if not step then
    set_lines(state.buffers.explanation, { "# Code Reader", "", "No step selected." })
    return
  end

  local source_ref = step.sources[1]
  local status = source_ref and source.status(source_ref, {
    root = state.root,
    explanation_path = state.path,
  }) or nil

  local lines = {
    "# " .. step.id .. " " .. step.title,
    "",
    "Step: " .. tostring(state.current) .. " / " .. tostring(#state.doc.steps),
    "Source: " .. source_ref_label(source_ref),
    "Status: " .. source.status_label(status),
    "",
  }

  for _, line in ipairs(split_lines(step.content)) do
    table.insert(lines, line)
  end

  append_navigation(lines, state, step, source_ref)

  set_lines(state.buffers.explanation, lines)
end

function M.render_toc(state)
  if not valid_buf(state.buffers.toc) then
    return
  end

  local lines = {}
  state.toc_line_to_step = {}

  for index, step in ipairs(state.doc.steps) do
    local indent = string.rep("  ", math.max(0, (step.depth or 1) - 1))
    local marker = index == state.current and "> " or "  "
    local line = marker .. indent .. step.id .. " " .. step.title
    table.insert(lines, line)
    state.toc_line_to_step[#lines] = index
  end

  if #lines == 0 then
    lines = { "No steps." }
  end

  set_lines(state.buffers.toc, lines)

  if valid_win(state.windows.toc) then
    vim.api.nvim_buf_clear_namespace(state.buffers.toc, namespace, 0, -1)
    if state.current <= #lines then
      vim.api.nvim_buf_set_extmark(state.buffers.toc, namespace, state.current - 1, 0, {
        line_hl_group = "CodeReaderCurrentStep",
      })
    end
  end
end

function M.render_source(state)
  local step = state.doc.steps[state.current]
  if not step or not step.sources[1] or not valid_win(state.windows.code) then
    return
  end

  local source_ref = step.sources[1]
  local path = source.resolve_path(source_ref, { root = state.root })
  if vim.fn.filereadable(path) ~= 1 then
    vim.notify("Code Reader: source file not found: " .. path, vim.log.levels.WARN)
    return
  end

  local previous_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(state.windows.code)

  local current_path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p")
  if current_path ~= path then
    local ok, err = pcall(vim.cmd, "keepalt edit " .. vim.fn.fnameescape(path))
    if not ok then
      vim.notify("Code Reader: cannot open source: " .. tostring(err), vim.log.levels.ERROR)
      if valid_win(previous_win) then
        vim.api.nvim_set_current_win(previous_win)
      end
      return
    end
  end

  local buf = vim.api.nvim_get_current_buf()
  local line_count = vim.api.nvim_buf_line_count(buf)
  local start_line = math.max(1, math.min(source_ref.start_line, line_count))
  local end_line = math.max(start_line, math.min(source_ref.end_line or source_ref.start_line, line_count))

  vim.api.nvim_win_set_cursor(state.windows.code, { start_line, 0 })
  vim.cmd("normal! zz")

  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  for line = 1, line_count do
    if line >= start_line and line <= end_line then
      vim.api.nvim_buf_set_extmark(buf, namespace, line - 1, 0, {
        line_hl_group = "CodeReaderActiveLine",
      })
    elseif state.focus and line_count <= (state.options.max_dim_lines or 5000) then
      vim.api.nvim_buf_add_highlight(buf, namespace, "CodeReaderDimLine", line - 1, 0, -1)
    end
  end

  if valid_win(previous_win) then
    vim.api.nvim_set_current_win(previous_win)
  end
end

function M.render(state)
  M.render_explanation(state)
  M.render_toc(state)
  M.render_source(state)
end

function M.reset_explanation_view(state)
  if not valid_win(state.windows and state.windows.explanation) then
    return
  end

  local previous_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(state.windows.explanation)
  vim.api.nvim_win_set_cursor(state.windows.explanation, { 1, 0 })
  vim.cmd("normal! zt")
  if valid_win(previous_win) then
    vim.api.nvim_set_current_win(previous_win)
  end
end

function M.clear_source_highlights(state)
  local code_win = state.windows and state.windows.code
  if not valid_win(code_win) then
    return
  end

  local buf = vim.api.nvim_win_get_buf(code_win)
  if valid_buf(buf) then
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  end
end

return M
