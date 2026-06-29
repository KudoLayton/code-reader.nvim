local parser = require("code_reader.parser")
local ui = require("code_reader.ui")
local source = require("code_reader.source")
local links = require("code_reader.links")
local symbols = require("code_reader.symbols")
local diff = require("code_reader.diff")

local M = {}

local state = {
  options = {
    focus = true,
    max_dim_lines = 5000,
    mermaid = {
      enabled = true,
      timeout_ms = 2000,
      use_ascii = false,
    },
  },
}

local function read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, lines
  end
  return table.concat(lines, "\n")
end

local function infer_root(path)
  local full = vim.fn.fnamemodify(path, ":p"):gsub("\\", "/")
  local marker = "/.code_reader/"
  local start_index = full:find(marker, 1, true)
  if start_index then
    return full:sub(1, start_index - 1)
  end
  return vim.fn.fnamemodify(full, ":h")
end

local function resolve_relative(base_path, target_path)
  if not target_path or target_path == "" then
    return nil
  end
  if target_path:match("^/") or target_path:match("^%a:[/\\]") then
    return vim.fn.fnamemodify(target_path, ":p")
  end
  return vim.fn.fnamemodify(vim.fn.fnamemodify(base_path, ":h") .. "/" .. target_path, ":p")
end

local function current_file()
  local name = vim.api.nvim_buf_get_name(0)
  if name == "" then
    return nil
  end
  return vim.fn.fnamemodify(name, ":p")
end

local function clamp_step(index)
  if not state.doc or #state.doc.steps == 0 then
    return 1
  end
  if index < 1 then
    return 1
  end
  if index > #state.doc.steps then
    return #state.doc.steps
  end
  return index
end

local function set_buffer_keymaps()
  if state.buffers and state.buffers.explanation and vim.api.nvim_buf_is_valid(state.buffers.explanation) then
    vim.keymap.set("n", "]r", function()
      require("code_reader").next()
    end, { buffer = state.buffers.explanation, silent = true, desc = "Code Reader next step" })

    vim.keymap.set("n", "[r", function()
      require("code_reader").prev()
    end, { buffer = state.buffers.explanation, silent = true, desc = "Code Reader previous step" })

    vim.keymap.set("n", "<CR>", function()
      require("code_reader").activate()
    end, { buffer = state.buffers.explanation, silent = true, desc = "Code Reader activate line" })

    vim.keymap.set("n", "q", function()
      require("code_reader").close()
    end, { buffer = state.buffers.explanation, silent = true, desc = "Code Reader close" })
  end

  if state.buffers and state.buffers.toc and vim.api.nvim_buf_is_valid(state.buffers.toc) then
    vim.keymap.set("n", "<CR>", function()
      require("code_reader").activate()
    end, { buffer = state.buffers.toc, silent = true, desc = "Code Reader activate TOC step" })

    vim.keymap.set("n", "q", function()
      require("code_reader").close()
    end, { buffer = state.buffers.toc, silent = true, desc = "Code Reader close" })
  end

  if state.buffers and state.buffers.front_page and vim.api.nvim_buf_is_valid(state.buffers.front_page) then
    vim.keymap.set("n", "<CR>", function()
      require("code_reader").activate()
    end, { buffer = state.buffers.front_page, silent = true, desc = "Code Reader activate front page link" })

    vim.keymap.set("n", "q", function()
      require("code_reader").close()
    end, { buffer = state.buffers.front_page, silent = true, desc = "Code Reader close" })
  end
end

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

function M.setup(opts)
  opts = opts or {}
  state.options = vim.tbl_deep_extend("force", state.options, opts)
  state.focus = state.options.focus ~= false
end

function M.open(path)
  path = path and path ~= "" and path or current_file()
  if not path then
    vim.notify("Code Reader: provide an explanation file path", vim.log.levels.ERROR)
    return
  end

  path = vim.fn.fnamemodify(path, ":p")
  local text, err = read_file(path)
  if not text then
    vim.notify("Code Reader: cannot read " .. path .. ": " .. tostring(err), vim.log.levels.ERROR)
    return
  end

  local doc = parser.parse(text, { path = path })
  local diff_doc = nil
  if doc.frontmatter.type == "code-reader-diff" then
    local diff_path = resolve_relative(path, doc.frontmatter.diff)
    local diff_text, diff_err = diff_path and read_file(diff_path) or nil, "missing diff frontmatter"
    if not diff_text then
      vim.notify("Code Reader: cannot read diff: " .. tostring(diff_err), vim.log.levels.ERROR)
      return
    end
    diff_doc = diff.parse(diff_text)
    diff_doc.path = diff_path
  elseif doc.frontmatter.type ~= "code-reader" then
    vim.notify("Code Reader: frontmatter type is not code-reader", vim.log.levels.WARN)
  end

  state.path = path
  state.root = infer_root(path)
  state.doc = doc
  state.diff = diff_doc
  state.current = 1
  state.focus = state.options.focus ~= false
  state.toc_line_to_step = {}

  ui.open_layout(state)
  set_buffer_keymaps()
  ui.render(state)
end

function M.goto_step(index, opts)
  opts = opts or {}
  if not state.doc then
    vim.notify("Code Reader: no explanation is open", vim.log.levels.WARN)
    return
  end

  state.current = clamp_step(tonumber(index) or state.current)
  symbols.clear()
  ui.render(state)
  ui.reset_explanation_view(state)
  if opts.keep_focus and valid_win(opts.keep_focus) then
    vim.api.nvim_set_current_win(opts.keep_focus)
  end
end

function M.next()
  M.goto_step((state.current or 1) + 1)
end

function M.prev()
  M.goto_step((state.current or 1) - 1)
end

function M.toggle_focus()
  state.focus = not state.focus
  ui.render(state)
  vim.notify("Code Reader: focus mode " .. (state.focus and "on" or "off"), vim.log.levels.INFO)
end

function M.open_source()
  if not state.doc then
    return
  end
  local step = state.doc.steps[state.current]
  if not step or not step.sources[1] then
    return
  end

  local path = source.resolve_path(step.sources[1], { root = state.root })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
end

function M.close()
  symbols.clear()
  ui.clear_source_highlights(state)
  ui.restore_code_buffer(state)

  local windows = state.windows or {}
  for _, name in ipairs({ "explanation", "toc", "diff_after" }) do
    local win = windows[name]
    if valid_win(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end

  local buffers = state.buffers or {}
  for _, name in ipairs({ "explanation", "toc", "front_page", "diff_before", "diff_after" }) do
    local buf = buffers[name]
    if valid_buf(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end

  state.path = nil
  state.root = nil
  state.doc = nil
  state.diff = nil
  state.current = nil
  state.toc_line_to_step = nil
  state.windows = nil
  state.buffers = nil
end

function M.activate()
  local buf = vim.api.nvim_get_current_buf()
  if state.buffers and buf == state.buffers.toc then
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local step = state.toc_line_to_step and state.toc_line_to_step[line]
    if step then
      M.goto_step(step, { keep_focus = buf == state.buffers.toc and vim.api.nvim_get_current_win() or nil })
    end
    return
  end

  local line = vim.api.nvim_get_current_line()
  if line:match("^%- Source:") then
    M.open_source()
    return
  end

  if not (state.buffers and (buf == state.buffers.explanation or buf == state.buffers.front_page)) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local link = links.find_at(line, cursor[2] + 1)
  if not link then
    return
  end

  if link.kind == "step" then
    local step_index = state.doc and state.doc.step_by_id and state.doc.step_by_id[link.target]
    if step_index then
      M.goto_step(step_index)
    else
      vim.notify("Code Reader: step not found: " .. link.target, vim.log.levels.WARN)
    end
  elseif link.kind == "treesitter" then
    symbols.highlight(state, link)
  elseif link.kind == "invalid" then
    vim.notify("Code Reader: invalid link: " .. link.reason, vim.log.levels.WARN)
  end
end

function M.state()
  return state
end

return M
