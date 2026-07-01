local M = {}

local function diff_fn()
  return vim.text and vim.text.diff or vim.diff
end

local function split_lines(text)
  local lines = {}
  if not text or text == "" then
    return lines
  end
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n") .. "\n"
  for line in text:gmatch("(.-)\n") do
    table.insert(lines, line)
  end
  return lines
end

local function table_contains(table_value, index)
  return table_value[index] == true
end

local function normalize_moved_line(line)
  return (line or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
end

local function make_cell(side, line_no, marker, kind, text, spans)
  return {
    side = side,
    line_no = line_no,
    marker = marker,
    kind = kind,
    text = text or "",
    spans = spans or {},
  }
end

local function make_blank(side)
  return make_cell(side, nil, "", "blank", "")
end

local function char_tokens(line)
  local tokens = {}
  local spans = {}
  local index = 1
  while index <= #line do
    table.insert(tokens, line:sub(index, index))
    table.insert(spans, { start_col = index - 1, end_col = index })
    index = index + 1
  end
  return tokens, spans
end

local function word_tokens(line)
  local tokens = {}
  local spans = {}
  local index = 1
  while index <= #line do
    local start_col, end_col = line:find("%s+", index)
    if start_col == index then
      table.insert(tokens, line:sub(start_col, end_col))
      table.insert(spans, { start_col = start_col - 1, end_col = end_col })
      index = end_col + 1
    else
      start_col, end_col = line:find("%w+", index)
      if start_col == index then
        table.insert(tokens, line:sub(start_col, end_col))
        table.insert(spans, { start_col = start_col - 1, end_col = end_col })
        index = end_col + 1
      else
        table.insert(tokens, line:sub(index, index))
        table.insert(spans, { start_col = index - 1, end_col = index })
        index = index + 1
      end
    end
  end
  return tokens, spans
end

local function token_text(tokens)
  return table.concat(tokens, "\n")
end

local function changed_token_indices(old_tokens, new_tokens)
  local changed_old = {}
  local changed_new = {}
  if #old_tokens == 0 and #new_tokens == 0 then
    return changed_old, changed_new
  end

  local fn = diff_fn()
  if not fn then
    for index = 1, #old_tokens do
      changed_old[index] = true
    end
    for index = 1, #new_tokens do
      changed_new[index] = true
    end
    return changed_old, changed_new
  end

  local ok, chunks = pcall(fn, token_text(old_tokens), token_text(new_tokens), {
    algorithm = "histogram",
    result_type = "indices",
  })
  if not ok or type(chunks) ~= "table" then
    for index = 1, #old_tokens do
      changed_old[index] = true
    end
    for index = 1, #new_tokens do
      changed_new[index] = true
    end
    return changed_old, changed_new
  end

  for _, chunk in ipairs(chunks) do
    local old_start, old_count, new_start, new_count = chunk[1], chunk[2], chunk[3], chunk[4]
    for index = old_start, old_start + old_count - 1 do
      changed_old[index] = true
    end
    for index = new_start, new_start + new_count - 1 do
      changed_new[index] = true
    end
  end

  return changed_old, changed_new
end

local function spans_from_changed(tokens, token_spans, changed)
  local spans = {}
  local current = nil
  for index = 1, #tokens do
    if table_contains(changed, index) and tokens[index]:match("%S") then
      local token_span = token_spans[index]
      if current and current.end_col == token_span.start_col then
        current.end_col = token_span.end_col
      else
        current = { start_col = token_span.start_col, end_col = token_span.end_col }
        table.insert(spans, current)
      end
    end
  end
  return spans
end

local function changed_spans(old_line, new_line)
  local old_tokens, old_token_spans = word_tokens(old_line)
  local new_tokens, new_token_spans = word_tokens(new_line)
  local changed_old, changed_new = changed_token_indices(old_tokens, new_tokens)
  local old_spans = spans_from_changed(old_tokens, old_token_spans, changed_old)
  local new_spans = spans_from_changed(new_tokens, new_token_spans, changed_new)

  if #old_spans == 0 and #new_spans == 0 and old_line ~= new_line then
    old_tokens, old_token_spans = char_tokens(old_line)
    new_tokens, new_token_spans = char_tokens(new_line)
    changed_old, changed_new = changed_token_indices(old_tokens, new_tokens)
    old_spans = spans_from_changed(old_tokens, old_token_spans, changed_old)
    new_spans = spans_from_changed(new_tokens, new_token_spans, changed_new)
  end

  return old_spans, new_spans
end

local function similarity(old_line, new_line)
  if old_line == new_line then
    return 1
  end
  local old_tokens = word_tokens(normalize_moved_line(old_line))
  local new_tokens = word_tokens(normalize_moved_line(new_line))
  local old_counts = {}
  local old_count = 0
  local new_count = 0

  for _, token in ipairs(old_tokens) do
    if token:match("%S") then
      old_counts[token] = (old_counts[token] or 0) + 1
      old_count = old_count + 1
    end
  end

  local common = 0
  for _, token in ipairs(new_tokens) do
    if token:match("%S") then
      new_count = new_count + 1
      if old_counts[token] and old_counts[token] > 0 then
        old_counts[token] = old_counts[token] - 1
        common = common + 1
      end
    end
  end

  if old_count == 0 and new_count == 0 then
    return 1
  end

  local denominator = math.max(old_count, new_count)
  return denominator > 0 and common / denominator or 0
end

local function line_counts(hunk)
  local old_line = hunk.old_start
  local new_line = hunk.new_start
  for _, entry in ipairs(hunk.lines or {}) do
    if entry.kind == "context" then
      entry.old_line = old_line
      entry.new_line = new_line
      old_line = old_line + 1
      new_line = new_line + 1
    elseif entry.kind == "delete" then
      entry.old_line = old_line
      old_line = old_line + 1
    elseif entry.kind == "add" then
      entry.new_line = new_line
      new_line = new_line + 1
    end
  end
end

local function moved_pairs(hunk)
  local add_by_text = {}
  local pairs = {}
  for index, entry in ipairs(hunk.lines or {}) do
    if entry.kind == "add" then
      local normalized = normalize_moved_line(entry.text)
      if normalized ~= "" then
        add_by_text[normalized] = add_by_text[normalized] or {}
        table.insert(add_by_text[normalized], index)
      end
    end
  end

  local used_add = {}
  local used_delete = {}
  for delete_index, entry in ipairs(hunk.lines or {}) do
    if entry.kind == "delete" then
      local normalized = normalize_moved_line(entry.text)
      local add_indexes = add_by_text[normalized]
      if normalized ~= "" and add_indexes then
        for _, add_index in ipairs(add_indexes) do
          if not used_add[add_index] then
            used_delete[delete_index] = add_index
            used_add[add_index] = delete_index
            table.insert(pairs, { delete_index = delete_index, add_index = add_index })
            break
          end
        end
      end
    end
  end

  return pairs, used_delete, used_add
end

local function collect_change_run(lines, start_index, used_delete, used_add)
  local deletes = {}
  local adds = {}
  local index = start_index
  while index <= #lines and lines[index].kind ~= "context" do
    local entry = lines[index]
    if entry.kind == "delete" and not used_delete[index] then
      table.insert(deletes, { index = index, entry = entry })
    elseif entry.kind == "add" and not used_add[index] then
      table.insert(adds, { index = index, entry = entry })
    end
    index = index + 1
  end
  return deletes, adds, index
end

local function append_modified_or_plain(rows, summary, delete_item, add_item)
  if delete_item and add_item and similarity(delete_item.entry.text, add_item.entry.text) >= 0.45 then
    local before_spans, after_spans = changed_spans(delete_item.entry.text, add_item.entry.text)
    table.insert(rows, {
      before = make_cell("before", delete_item.entry.old_line, "~", "modified", delete_item.entry.text, before_spans),
      after = make_cell("after", add_item.entry.new_line, "~", "modified", add_item.entry.text, after_spans),
    })
    summary.modified = summary.modified + 1
    return true
  end
  return false
end

local function append_change_run(rows, summary, deletes, adds)
  local paired_adds = {}
  local pair_by_delete = {}

  for delete_index, delete_item in ipairs(deletes) do
    local best_add_index = nil
    local best_score = 0
    for add_index, add_item in ipairs(adds) do
      if not paired_adds[add_index] then
        local score = similarity(delete_item.entry.text, add_item.entry.text)
        if score > best_score then
          best_score = score
          best_add_index = add_index
        end
      end
    end
    if best_add_index and best_score >= 0.45 then
      pair_by_delete[delete_index] = best_add_index
      paired_adds[best_add_index] = true
    end
  end

  local emitted_adds = {}
  for delete_index, delete_item in ipairs(deletes) do
    local add_index = pair_by_delete[delete_index]
    if add_index then
      append_modified_or_plain(rows, summary, delete_item, adds[add_index])
      emitted_adds[add_index] = true
    else
      table.insert(rows, {
        before = make_cell("before", delete_item.entry.old_line, "-", "deleted", delete_item.entry.text),
        after = make_blank("after"),
      })
      summary.deleted = summary.deleted + 1
    end
  end

  for add_index, add_item in ipairs(adds) do
    if not emitted_adds[add_index] then
      table.insert(rows, {
        before = make_blank("before"),
        after = make_cell("after", add_item.entry.new_line, "+", "added", add_item.entry.text),
      })
      summary.added = summary.added + 1
    end
  end
end

local function format_cell(cell, width)
  local line_no = cell.line_no and tostring(cell.line_no) or ""
  local prefix = string.format("%" .. tostring(width) .. "s %s ", line_no, cell.marker or "")
  cell.text_col = #prefix
  return prefix .. (cell.text or "")
end

local function max_line_width(hunk)
  local max_line = math.max(hunk.old_end or 0, hunk.new_end or 0)
  return math.max(1, #tostring(max_line))
end

local function format_rows(rows, width)
  local before_lines = {}
  local after_lines = {}
  for _, row in ipairs(rows) do
    table.insert(before_lines, format_cell(row.before or make_blank("before"), width))
    table.insert(after_lines, format_cell(row.after or make_blank("after"), width))
  end
  return before_lines, after_lines
end

local function render_hunk_rows(hunk)
  line_counts(hunk)
  local rows = {}
  local summary = {
    modified = 0,
    moved = 0,
    added = 0,
    deleted = 0,
  }
  local _, used_delete, used_add = moved_pairs(hunk)
  local lines = hunk.lines or {}
  local index = 1

  while index <= #lines do
    local entry = lines[index]
    if entry.kind == "context" then
      table.insert(rows, {
        before = make_cell("before", entry.old_line, "", "context", entry.text),
        after = make_cell("after", entry.new_line, "", "context", entry.text),
      })
      index = index + 1
    elseif entry.kind == "delete" and used_delete[index] then
      local add_index = used_delete[index]
      local add_entry = lines[add_index]
      table.insert(rows, {
        before = make_cell("before", entry.old_line, ">", "moved", entry.text),
        after = make_cell("after", add_entry.new_line, ">", "moved", add_entry.text),
      })
      summary.moved = summary.moved + 1
      index = index + 1
    elseif entry.kind == "add" and used_add[index] then
      index = index + 1
    else
      local deletes, adds, next_index = collect_change_run(lines, index, used_delete, used_add)
      append_change_run(rows, summary, deletes, adds)
      index = next_index
    end
  end

  return {
    rows = rows,
    summary = summary,
  }
end

local function annotate_rows(rows, hunk)
  for _, row in ipairs(rows or {}) do
    row.hunk = hunk
  end
end

function M.render_hunk(hunk, opts)
  opts = opts or {}
  local model = render_hunk_rows(hunk)
  annotate_rows(model.rows, hunk)
  local width = opts.width or max_line_width(hunk)
  local before_lines, after_lines = format_rows(model.rows, width)
  model.before_lines = before_lines
  model.after_lines = after_lines
  model.gutter_width = width + 3
  model.focus_start = 1
  model.focus_end = #model.rows
  local range = opts.side and M.resolve_hunk_range(hunk, opts.side, opts) or nil
  if range then
    local focus_start = nil
    local focus_end = nil
    for index, row in ipairs(model.rows) do
      local cell = opts.side == "old" and row.before or row.after
      if cell and cell.line_no and cell.line_no >= range.start_line and cell.line_no <= range.end_line then
        focus_start = focus_start or index
        focus_end = index
      end
    end
    model.focus_start = focus_start or model.focus_start
    model.focus_end = focus_end or model.focus_end
  end
  return model
end

local function resolve_bound(hunk, side, bound, is_start)
  if not bound then
    return nil
  end
  if bound.mode == "absolute" then
    return bound.value
  end
  local base = nil
  if side == "old" then
    base = is_start and hunk.old_start or hunk.old_end
  else
    base = is_start and hunk.new_start or hunk.new_end
  end
  return base + bound.value
end

function M.resolve_hunk_range(hunk, side, opts)
  if not (hunk and side) then
    return nil
  end
  opts = opts or {}

  local start_line = nil
  local end_line = nil
  if opts.padding then
    local padding = math.max(0, tonumber(opts.padding) or 0)
    if side == "old" then
      start_line = hunk.old_start - padding
      end_line = hunk.old_end + padding
    else
      start_line = hunk.new_start - padding
      end_line = hunk.new_end + padding
    end
  elseif opts.start_bound and opts.end_bound then
    start_line = resolve_bound(hunk, side, opts.start_bound, true)
    end_line = resolve_bound(hunk, side, opts.end_bound, false)
  end

  if not (start_line and end_line) then
    return nil
  end
  start_line = math.max(1, start_line)
  end_line = math.max(start_line, end_line)
  return {
    side = side,
    start_line = start_line,
    end_line = end_line,
  }
end

local function append_unchanged_rows(rows, before_lines, after_lines, old_cursor, new_cursor, old_stop, new_stop)
  while old_cursor < old_stop and new_cursor < new_stop do
    table.insert(rows, {
      before = make_cell("before", old_cursor, "", "context", before_lines[old_cursor] or ""),
      after = make_cell("after", new_cursor, "", "context", after_lines[new_cursor] or ""),
    })
    old_cursor = old_cursor + 1
    new_cursor = new_cursor + 1
  end
  return old_cursor, new_cursor
end

local function append_remaining_rows(rows, before_lines, after_lines, old_cursor, new_cursor)
  while old_cursor <= #before_lines or new_cursor <= #after_lines do
    local before = old_cursor <= #before_lines
        and make_cell("before", old_cursor, "", "context", before_lines[old_cursor] or "")
      or make_blank("before")
    local after = new_cursor <= #after_lines
        and make_cell("after", new_cursor, "", "context", after_lines[new_cursor] or "")
      or make_blank("after")
    table.insert(rows, { before = before, after = after })
    old_cursor = old_cursor + 1
    new_cursor = new_cursor + 1
  end
end

function M.render_file(file, before_lines, after_lines, focus_hunk, diff_ref, opts)
  opts = opts or {}
  local rows = {}
  local old_cursor = 1
  local new_cursor = 1
  local focus_start = 1
  local focus_end = 1

  for _, hunk in ipairs(file.hunks or {}) do
    if not opts.only_hunk or hunk == focus_hunk then
      old_cursor, new_cursor = append_unchanged_rows(
        rows,
        before_lines,
        after_lines,
        old_cursor,
        new_cursor,
        hunk.old_start,
        hunk.new_start
      )

      local hunk_model = render_hunk_rows(hunk)
      annotate_rows(hunk_model.rows, hunk)
      if hunk == focus_hunk then
        focus_start = #rows + 1
        focus_end = #rows + #hunk_model.rows
      end
      for _, row in ipairs(hunk_model.rows) do
        table.insert(rows, row)
      end
      old_cursor = hunk.old_start + hunk.old_count
      new_cursor = hunk.new_start + hunk.new_count
    end
  end

  append_remaining_rows(rows, before_lines, after_lines, old_cursor, new_cursor)

  local width = math.max(1, #tostring(math.max(#before_lines, #after_lines)))
  local rendered_before, rendered_after = format_rows(rows, width)
  local model = {
    rows = rows,
    before_lines = rendered_before,
    after_lines = rendered_after,
    focus_start = focus_start,
    focus_end = focus_end,
    gutter_width = width + 3,
  }

  local range = diff_ref and diff_ref.side and M.resolve_hunk_range(focus_hunk, diff_ref.side, diff_ref) or nil
  if range then
    local range_focus_start = nil
    local range_focus_end = nil
    for index, row in ipairs(rows) do
      local cell = diff_ref.side == "old" and row.before or row.after
      if cell and cell.line_no and cell.line_no >= range.start_line and cell.line_no <= range.end_line then
        range_focus_start = range_focus_start or index
        range_focus_end = index
      end
    end
    if range_focus_start and range_focus_end then
      model.focus_start = range_focus_start
      model.focus_end = range_focus_end
    end
  end

  return model
end

function M.summary_label(summary)
  summary = summary or {}
  return string.format(
    "%d modified pair%s, %d moved line%s, %d addition%s, %d deletion%s",
    summary.modified or 0,
    (summary.modified or 0) == 1 and "" or "s",
    summary.moved or 0,
    (summary.moved or 0) == 1 and "" or "s",
    summary.added or 0,
    (summary.added or 0) == 1 and "" or "s",
    summary.deleted or 0,
    (summary.deleted or 0) == 1 and "" or "s"
  )
end

return M
