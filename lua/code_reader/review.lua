local refcopy = require("code_reader.refcopy")

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

local function review_path(walkthrough_path)
  local sidecar = walkthrough_path:gsub("%.md$", ".reviews.jsonl")
  if sidecar == walkthrough_path then
    sidecar = walkthrough_path .. ".reviews.jsonl"
  end
  return sidecar
end

local function comment_text(buffer)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local first = 1
  local last = #lines
  while first <= last and not lines[first]:match("%S") do
    first = first + 1
  end
  while last >= first and not lines[last]:match("%S") do
    last = last - 1
  end
  if first > last then
    return nil
  end
  return table.concat(vim.list_slice(lines, first, last), "\n")
end

local function target_kind(state, buffer)
  local buffers = state and state.buffers or {}
  if buffer == buffers.diff_before or buffer == buffers.diff_after then
    return "diff"
  end
  local code_window = state and state.windows and state.windows.code or nil
  if code_window and vim.api.nvim_win_is_valid(code_window) and vim.api.nvim_win_get_buf(code_window) == buffer then
    local name = vim.api.nvim_buf_get_name(buffer)
    if name ~= "" and not name:match("^code%-reader://") then
      return "source"
    end
  end
  return nil
end

local function selected_evidence_id(state, kind)
  local step = state.doc and state.doc.steps and state.doc.steps[state.current] or nil
  if not step then
    return nil
  end
  if state.selected_evidence and step.evidence_by_id and step.evidence_by_id[state.selected_evidence] then
    return state.selected_evidence
  end
  for _, evidence in ipairs(step.evidence or {}) do
    if evidence.kind == kind then
      return evidence.id
    end
  end
  return nil
end

local function write_entry(path, entry)
  local directory = vim.fn.fnamemodify(path, ":h")
  if vim.fn.mkdir(directory, "p") ~= 1 and vim.fn.isdirectory(directory) ~= 1 then
    return nil, "cannot create review directory: " .. directory
  end
  local ok, err = pcall(vim.fn.writefile, { vim.json.encode(entry) }, path, "a")
  if not ok then
    return nil, tostring(err)
  end
  return true
end

local function close_window(window)
  if window and vim.api.nvim_win_is_valid(window) then
    vim.api.nvim_win_close(window, true)
  end
end

local function open_input(entry, path)
  local buffer = vim.api.nvim_create_buf(false, true)
  local width = math.max(48, math.min(vim.o.columns - 4, math.floor(vim.o.columns * 0.62)))
  local height = math.max(8, math.min(vim.o.lines - 4, math.floor(vim.o.lines * 0.38)))
  local window = vim.api.nvim_open_win(buffer, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(1, math.floor((vim.o.lines - height) / 2)),
    col = math.max(1, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = "rounded",
    title = " Code Reader comment ",
    title_pos = "center",
  })

  vim.api.nvim_buf_set_name(buffer, "code-reader://review/" .. tostring(vim.uv.hrtime()))
  vim.api.nvim_set_option_value("buftype", "acwrite", { buf = buffer })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buffer })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buffer })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buffer })
  vim.api.nvim_set_option_value("winhighlight", "Normal:NormalFloat,FloatBorder:FloatBorder", { win = window })
  vim.keymap.set("n", "q", function()
    close_window(window)
  end, { buffer = buffer, silent = true, desc = "Discard Code Reader comment" })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buffer,
    callback = function()
      local comment = comment_text(buffer)
      if not comment then
        vim.bo[buffer].modified = false
        vim.notify("Code Reader: empty comment discarded", vim.log.levels.INFO)
        return
      end
      entry.comment = comment
      local ok, err = write_entry(path, entry)
      if not ok then
        vim.notify("Code Reader: could not save comment: " .. tostring(err), vim.log.levels.ERROR)
        return
      end
      vim.bo[buffer].modified = false
      vim.notify("Code Reader: comment saved", vim.log.levels.INFO)
    end,
  })

  return true
end

function M.add(state, opts)
  opts = opts or {}
  if not (state and state.doc and state.path and state.root) then
    vim.notify("Code Reader: open a walkthrough before adding a comment", vim.log.levels.WARN)
    return false
  end

  local buffer = opts.bufnr or vim.api.nvim_get_current_buf()
  local kind = target_kind(state, buffer)
  if not kind then
    vim.notify("Code Reader: comments can only target a source or diff panel", vim.log.levels.WARN)
    return false
  end

  local reference, reference_kind = refcopy.reference(state, {
    bufnr = buffer,
    line1 = opts.line1,
    line2 = opts.line2,
  })
  if not reference or reference_kind ~= kind then
    vim.notify("Code Reader: select one concrete source or diff range", vim.log.levels.WARN)
    return false
  end

  local step = state.doc.steps[state.current]
  local entry = {
    version = 1,
    walkthrough = relative_path(state.path, state.root),
    stage_id = step and step.id or nil,
    evidence_id = selected_evidence_id(state, kind),
    kind = kind,
    reference = reference,
    created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }
  return open_input(entry, review_path(state.path))
end

return M
