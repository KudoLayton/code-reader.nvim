local source = require("code_reader.source")
local mermaid = require("code_reader.mermaid")
local diff = require("code_reader.diff")
local diff_render = require("code_reader.diff_render")
local syntax = require("code_reader.syntax")

local M = {}

local namespace = vim.api.nvim_create_namespace("code-reader")
local link_namespace = vim.api.nvim_create_namespace("code-reader-links")

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

local function render_markdown_lines(text, state)
  return mermaid.render_lines(split_lines(text), state.options and state.options.mermaid or {})
end

local function add_range_highlight(buf, line_index, start_col, end_col, group)
  if start_col and end_col and end_col > start_col then
    vim.api.nvim_buf_set_extmark(buf, link_namespace, line_index, start_col, {
      end_col = end_col,
      hl_group = group,
      priority = 120,
    })
  end
end

local function add_pattern_highlights(buf, line_index, line, pattern, group)
  local cursor = 1
  while cursor <= #line do
    local start_index, end_index = line:find(pattern, cursor)
    if not start_index then
      break
    end
    add_range_highlight(buf, line_index, start_index - 1, end_index, group)
    cursor = end_index + 1
  end
end

local function add_target_highlight(buf, line_index, line, label, group)
  local label_start, label_end = line:find(label .. ":%s*")
  if not label_start then
    return
  end

  local target_start = label_end + 1
  local target_end = nil
  if line:sub(target_start, target_start) == "`" then
    target_start = target_start + 1
    target_end = line:find("`", target_start, true)
    target_end = target_end and target_end - 1 or #line
  else
    target_end = line:find("%s", target_start)
    target_end = target_end and target_end - 1 or #line
  end

  add_range_highlight(buf, line_index, target_start - 1, target_end, group)
end

local function highlight_code_reader_links(buf)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end

  vim.api.nvim_buf_clear_namespace(buf, link_namespace, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for index, line in ipairs(lines) do
    local line_index = index - 1
    add_pattern_highlights(buf, line_index, line, "%[%[[^%]]-%]%]", "CodeReaderStepLink")
    add_pattern_highlights(buf, line_index, line, "%[[^%]]-%]%(<treesitter://.-%>%)", "CodeReaderSymbolLink")
    add_target_highlight(buf, line_index, line, "Source", "CodeReaderSourceTarget")
    add_target_highlight(buf, line_index, line, "Diff", "CodeReaderDiffTarget")
  end
end

local function render_markdown_buffer(buf, win)
  local ok, render_markdown = pcall(require, "render-markdown")
  if not ok or type(render_markdown.render) ~= "function" then
    syntax.highlight_markdown(buf)
    highlight_code_reader_links(buf)
    return
  end

  pcall(render_markdown.render, {
    buf = buf,
    win = win,
    event = "CodeReader",
    config = {
      link = {
        custom = {
          code_reader_symbol = {
            icon = "CR ",
            pattern = "^treesitter://",
          },
        },
      },
    },
  })

  syntax.highlight_markdown(buf)
  highlight_code_reader_links(buf)
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

local function step_link_with_position(step, current_source_ref)
  local target_source_ref = step.sources and step.sources[1] or nil
  local suffix = nil

  if not target_source_ref then
    suffix = " (no source)"
  elseif not current_source_ref or current_source_ref.path ~= target_source_ref.path then
    suffix = " (↗ " .. source_ref_label(target_source_ref) .. ")"
  else
    local delta = target_source_ref.start_line - current_source_ref.start_line
    if delta < 0 then
      suffix = " (↑" .. tostring(math.abs(delta)) .. ")"
    elseif delta > 0 then
      suffix = " (↓" .. tostring(delta) .. ")"
    else
      suffix = " (=)"
    end
  end

  return step_link(step) .. suffix
end

local function is_front_page(step)
  return step and step.kind == "front_page"
end

local function is_diff_mode(state)
  return state and state.diff ~= nil
end

local function read_source_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end
  return lines
end

local function diff_ref_label(diff_ref)
  if not diff_ref then
    return "none"
  end
  return diff_ref.path .. "#" .. diff_ref.hunk_id
end

local function find_diff_target(state, diff_ref)
  if not (state and state.diff and diff_ref) then
    return nil, nil
  end
  local file = state.diff.file_by_path[diff_ref.path]
  local hunk = file and file.hunk_by_id and file.hunk_by_id[diff_ref.hunk_id]
  return file, hunk
end

local function step_link_with_diff_position(state, step, current_diff_ref)
  local target_diff_ref = step.diff_refs and step.diff_refs[1] or nil
  local suffix = nil

  if not target_diff_ref then
    suffix = " (no diff)"
  else
    local target_file, target_hunk = find_diff_target(state, target_diff_ref)
    local current_file, current_hunk = find_diff_target(state, current_diff_ref)
    if not (target_file and target_hunk) then
      suffix = " (missing diff)"
    elseif not (current_file and current_hunk) or current_file.path ~= target_file.path then
      suffix = " (↗ " .. diff_ref_label(target_diff_ref) .. ")"
    else
      local delta = target_hunk.new_start - current_hunk.new_start
      if delta < 0 then
        suffix = " (↑" .. tostring(math.abs(delta)) .. " " .. diff_ref_label(target_diff_ref) .. ")"
      elseif delta > 0 then
        suffix = " (↓" .. tostring(delta) .. " " .. diff_ref_label(target_diff_ref) .. ")"
      else
        suffix = " (= " .. diff_ref_label(target_diff_ref) .. ")"
      end
    end
  end

  return step_link(step) .. suffix
end

local function analyze_diff_file(state, file)
  if not file then
    return { status = "missing", before_lines = {}, after_lines = {} }
  end
  local path = source.resolve_path({ path = file.path }, { root = state.root })
  local lines = read_source_lines(path)
  if not lines then
    return { status = "missing", before_lines = {}, after_lines = {} }
  end
  return diff.analyze_file(file, lines)
end

local function diff_view_label(analysis)
  if analysis and (analysis.status == "applies" or analysis.status == "already-applied") then
    return "full file side-by-side"
  end
  return "patch-only side-by-side"
end

local function diff_line_hl(kind)
  if kind == "deleted" then
    return "CodeReaderDiffDelete"
  end
  if kind == "added" then
    return "CodeReaderDiffAdd"
  end
  if kind == "modified" then
    return "CodeReaderDiffModify"
  end
  if kind == "moved" then
    return "CodeReaderDiffMove"
  end
  if kind == "blank" then
    return "CodeReaderDiffFiller"
  end
  return nil
end

local function apply_diff_cell_highlight(buf, line_index, cell, gutter_width, in_focus)
  if not cell then
    return
  end

  local line_hl = diff_line_hl(cell.kind)
  if line_hl then
    vim.api.nvim_buf_set_extmark(buf, namespace, line_index, 0, {
      line_hl_group = line_hl,
    })
  elseif in_focus and cell.kind == "context" then
    vim.api.nvim_buf_set_extmark(buf, namespace, line_index, 0, {
      line_hl_group = "CodeReaderActiveLine",
    })
  end

  if cell.kind == "modified" then
    for _, span in ipairs(cell.spans or {}) do
      if span.end_col > span.start_col then
        vim.api.nvim_buf_set_extmark(buf, namespace, line_index, gutter_width + span.start_col, {
          end_col = gutter_width + span.end_col,
          hl_group = "CodeReaderDiffWord",
          priority = 10010,
        })
      end
    end
  end
end

local function apply_diff_highlights(model, before_buf, after_buf, state)
  vim.api.nvim_buf_clear_namespace(before_buf, namespace, 0, -1)
  vim.api.nvim_buf_clear_namespace(after_buf, namespace, 0, -1)

  local row_count = #(model.rows or {})
  local should_dim = state
    and state.focus
    and row_count <= (state.options.max_dim_lines or 5000)
    and model.focus_start
    and model.focus_end
    and row_count > (model.focus_end - model.focus_start + 1)

  for index, row in ipairs(model.rows or {}) do
    local in_focus = index >= (model.focus_start or 1) and index <= (model.focus_end or row_count)
    apply_diff_cell_highlight(before_buf, index - 1, row.before, model.gutter_width or 0, in_focus)
    apply_diff_cell_highlight(after_buf, index - 1, row.after, model.gutter_width or 0, in_focus)
    if should_dim and not in_focus then
      vim.api.nvim_buf_add_highlight(before_buf, namespace, "CodeReaderDimLine", index - 1, 0, -1)
      vim.api.nvim_buf_add_highlight(after_buf, namespace, "CodeReaderDimLine", index - 1, 0, -1)
    end
  end
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
  local current_diff_ref = step.diff_refs and step.diff_refs[1] or nil
  local link_with_position = function(target_step)
    if is_diff_mode(state) then
      return step_link_with_diff_position(state, target_step, current_diff_ref)
    end
    return step_link_with_position(target_step, source_ref)
  end

  if previous then
    table.insert(lines, "- Previous: " .. link_with_position(previous))
  end
  if next_step then
    table.insert(lines, "- Next: " .. link_with_position(next_step))
  end
  if parent then
    table.insert(lines, "- Parent: " .. link_with_position(parent))
  end
  if #children > 0 then
    table.insert(lines, "- Children:")
    for _, child in ipairs(children) do
      table.insert(lines, "  - " .. link_with_position(child))
    end
  end

  if is_diff_mode(state) then
    table.insert(lines, "- Diff: `" .. diff_ref_label(current_diff_ref) .. "`")
  else
    table.insert(lines, "- Source: `" .. source_ref_label(source_ref) .. "`")
  end
end

local function collect_source_paths(state)
  local paths = {}
  local seen = {}

  for _, step in ipairs(state.doc.steps or {}) do
    if not is_front_page(step) then
      for _, source_ref in ipairs(step.sources or {}) do
        local path = source_ref.path
        if path and not seen[path] then
          table.insert(paths, path)
          seen[path] = true
        end
      end
    end
  end

  return paths
end

local function append_front_page_toc(lines, state)
  local count = 0
  for _, step in ipairs(state.doc.steps or {}) do
    if not is_front_page(step) then
      local indent = string.rep("  ", math.max(0, (step.depth or 1) - 1))
      table.insert(lines, indent .. "- " .. step_link(step))
      count = count + 1
    end
  end

  if count == 0 then
    table.insert(lines, "- none")
  end
end

local function count_diff_hunks(state)
  local count = 0
  for _, file in ipairs((state.diff and state.diff.files) or {}) do
    count = count + #(file.hunks or {})
  end
  return count
end

local function diff_coverage(state)
  local explained = 0
  local explained_hunks = 0
  local seen = {}
  local sections = {}

  for _, step in ipairs(state.doc.steps or {}) do
    if not is_front_page(step) then
      local section_lines = 0
      local section_hunks = 0
      for _, diff_ref in ipairs(step.diff_refs or {}) do
        local file, hunk = find_diff_target(state, diff_ref)
        if file and hunk then
          section_lines = section_lines + hunk.changed_lines
          section_hunks = section_hunks + 1
          local key = file.path .. "#" .. hunk.id
          if not seen[key] then
            seen[key] = true
            explained = explained + hunk.changed_lines
            explained_hunks = explained_hunks + 1
          end
        end
      end
      if section_hunks > 0 then
        table.insert(sections, {
          step = step,
          changed_lines = section_lines,
          hunks = section_hunks,
        })
      end
    end
  end

  return {
    explained = explained,
    explained_hunks = explained_hunks,
    total = state.diff and state.diff.total_changed_lines or 0,
    total_hunks = count_diff_hunks(state),
    sections = sections,
  }
end

local function append_diff_coverage(lines, state)
  local coverage = diff_coverage(state)
  local percent = coverage.total > 0 and (coverage.explained / coverage.total * 100) or 0

  table.insert(lines, "")
  table.insert(lines, "## Diff Coverage")
  table.insert(lines, "")
  table.insert(
    lines,
    string.format("Explained changes: %d / %d (%.1f%%)", coverage.explained, coverage.total, percent)
  )
  table.insert(lines, string.format("Explained hunks: %d / %d", coverage.explained_hunks, coverage.total_hunks))
  table.insert(lines, "")
  table.insert(lines, "### Sections")
  table.insert(lines, "")
  if #coverage.sections == 0 then
    table.insert(lines, "- none")
  else
    for _, section in ipairs(coverage.sections) do
      local section_percent = coverage.total > 0 and (section.changed_lines / coverage.total * 100) or 0
      table.insert(
        lines,
        string.format(
          "- %s: %d changed lines, %d hunks (%.1f%%)",
          step_link(section.step),
          section.changed_lines,
          section.hunks,
          section_percent
        )
      )
    end
  end
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
  vim.api.nvim_set_hl(0, "CodeReaderDiffDelete", { bg = "#3f1f24", default = true })
  vim.api.nvim_set_hl(0, "CodeReaderDiffAdd", { bg = "#1f3a2b", default = true })
  vim.api.nvim_set_hl(0, "CodeReaderDiffModify", { bg = "#3a3420", default = true })
  vim.api.nvim_set_hl(0, "CodeReaderDiffMove", { bg = "#23324a", default = true })
  vim.api.nvim_set_hl(0, "CodeReaderDiffFiller", { fg = "#4b5563", default = true })
  vim.api.nvim_set_hl(0, "CodeReaderDiffWord", { bg = "#6b4f1d", bold = true, default = true })
  vim.api.nvim_set_hl(0, "CodeReaderStepLink", { fg = "#93c5fd", underline = true, default = true })
  vim.api.nvim_set_hl(0, "CodeReaderSymbolLink", { fg = "#c4b5fd", underline = true, default = true })
  vim.api.nvim_set_hl(0, "CodeReaderSourceTarget", { fg = "#86efac", bold = true, default = true })
  vim.api.nvim_set_hl(0, "CodeReaderDiffTarget", { fg = "#fca5a5", bold = true, default = true })
end

function M.open_layout(state)
  M.setup_highlights()

  state.windows = state.windows or {}
  state.buffers = state.buffers or {}

  state.windows.code = vim.api.nvim_get_current_win()
  state.buffers.code = vim.api.nvim_win_get_buf(state.windows.code)
  state.buffers.front_page = create_scratch("code-reader://front-page", "markdown")
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = state.buffers.front_page })
  if is_diff_mode(state) then
    state.buffers.diff_before = create_scratch("code-reader://diff-before", "diff")
    state.buffers.diff_after = create_scratch("code-reader://diff-after", "diff")
    vim.api.nvim_set_option_value("bufhidden", "hide", { buf = state.buffers.diff_before })
    vim.api.nvim_set_option_value("bufhidden", "hide", { buf = state.buffers.diff_after })
    vim.cmd("vsplit")
    state.windows.diff_after = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.windows.diff_after, state.buffers.diff_after)
  end
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

  if is_front_page(step) then
    local lines = {
      "# " .. step.id .. " " .. step.title,
      "",
      "Step: " .. tostring(state.current) .. " / " .. tostring(#state.doc.steps),
      "Source: none",
      "Status: overview",
      "",
    }

    append_navigation(lines, state, step, nil)
    set_lines(state.buffers.explanation, lines)
    render_markdown_buffer(state.buffers.explanation, state.windows.explanation)
    return
  end

  if is_diff_mode(state) then
    local diff_ref = step.diff_refs and step.diff_refs[1] or nil
    local file, hunk = find_diff_target(state, diff_ref)
    local analysis = analyze_diff_file(state, file)
    local lines = {
      "# " .. step.id .. " " .. step.title,
      "",
      "Step: " .. tostring(state.current) .. " / " .. tostring(#state.doc.steps),
      "Diff: " .. diff_ref_label(diff_ref),
      "View: " .. diff_view_label(analysis),
      "Status: " .. (analysis.status or "unknown"),
    }

    if file and hunk then
      table.insert(lines, diff.hunk_ref_label(file, hunk))
      table.insert(lines, "Rendering: " .. diff_render.summary_label(diff_render.render_hunk(hunk).summary))
    end
    table.insert(lines, "")

    for _, line in ipairs(render_markdown_lines(step.content, state)) do
      table.insert(lines, line)
    end

    append_navigation(lines, state, step, nil)
    set_lines(state.buffers.explanation, lines)
    render_markdown_buffer(state.buffers.explanation, state.windows.explanation)
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

  for _, line in ipairs(render_markdown_lines(step.content, state)) do
    table.insert(lines, line)
  end

  append_navigation(lines, state, step, source_ref)

  set_lines(state.buffers.explanation, lines)
  render_markdown_buffer(state.buffers.explanation, state.windows.explanation)
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

function M.render_front_page(state)
  local step = state.doc.steps[state.current]
  if not is_front_page(step) or not valid_win(state.windows.code) or not valid_buf(state.buffers.front_page) then
    return
  end

  local lines = {
    "# " .. step.title,
    "",
  }

  for _, line in ipairs(render_markdown_lines(step.content, state)) do
    table.insert(lines, line)
  end

  if is_diff_mode(state) then
    append_diff_coverage(lines, state)
  end

  table.insert(lines, "")
  table.insert(lines, is_diff_mode(state) and "## Diff Targets" or "## Explanation Targets")
  table.insert(lines, "")

  local paths = {}
  if is_diff_mode(state) then
    for _, file in ipairs((state.diff and state.diff.files) or {}) do
      if file.path then
        table.insert(paths, file.path)
      end
    end
  else
    paths = collect_source_paths(state)
  end
  if #paths == 0 then
    table.insert(lines, "- none")
  else
    for _, path in ipairs(paths) do
      table.insert(lines, "- `" .. path .. "`")
    end
  end

  table.insert(lines, "")
  table.insert(lines, "## Table of Contents")
  table.insert(lines, "")
  append_front_page_toc(lines, state)

  set_lines(state.buffers.front_page, lines)
  vim.api.nvim_win_set_buf(state.windows.code, state.buffers.front_page)
  vim.api.nvim_win_set_cursor(state.windows.code, { 1, 0 })
  render_markdown_buffer(state.buffers.front_page, state.windows.code)
end

function M.render_source(state)
  local step = state.doc.steps[state.current]
  if is_front_page(step) then
    M.render_front_page(state)
    return
  end

  if is_diff_mode(state) then
    if not (valid_win(state.windows.code) and valid_win(state.windows.diff_after)) then
      return
    end

    local diff_ref = step.diff_refs and step.diff_refs[1] or nil
    local file, hunk = find_diff_target(state, diff_ref)
    if not (file and hunk) then
      return
    end

    local analysis = analyze_diff_file(state, file)
    local model = nil
    local cursor_line = 1
    local full_view = analysis.status == "applies" or analysis.status == "already-applied"

    if full_view then
      model = diff_render.render_file(file, analysis.before_lines, analysis.after_lines, hunk)
      cursor_line = model.focus_start or 1
    else
      model = diff_render.render_hunk(hunk)
      cursor_line = 1
    end

    set_lines(state.buffers.diff_before, model.before_lines)
    set_lines(state.buffers.diff_after, model.after_lines)
    vim.api.nvim_win_set_buf(state.windows.code, state.buffers.diff_before)
    vim.api.nvim_win_set_buf(state.windows.diff_after, state.buffers.diff_after)

    local before_count = math.max(1, vim.api.nvim_buf_line_count(state.buffers.diff_before))
    local after_count = math.max(1, vim.api.nvim_buf_line_count(state.buffers.diff_after))
    cursor_line = math.max(1, math.min(cursor_line, math.min(before_count, after_count)))
    vim.api.nvim_win_set_cursor(state.windows.code, { cursor_line, 0 })
    vim.api.nvim_win_set_cursor(state.windows.diff_after, { cursor_line, 0 })

    apply_diff_highlights(model, state.buffers.diff_before, state.buffers.diff_after, state)
    syntax.highlight_diff(state.buffers.diff_before, model.rows, "before", file.path, model.gutter_width or 0)
    syntax.highlight_diff(state.buffers.diff_after, model.rows, "after", file.path, model.gutter_width or 0)
    return
  end

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

function M.restore_code_buffer(state)
  local code_win = state.windows and state.windows.code
  local code_buf = state.buffers and state.buffers.code
  local front_page_buf = state.buffers and state.buffers.front_page
  local diff_before_buf = state.buffers and state.buffers.diff_before
  if not (valid_win(code_win) and valid_buf(code_buf)) then
    return
  end
  local current_buf = vim.api.nvim_win_get_buf(code_win)
  if current_buf == front_page_buf or current_buf == diff_before_buf then
    pcall(vim.api.nvim_win_set_buf, code_win, code_buf)
  end
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
