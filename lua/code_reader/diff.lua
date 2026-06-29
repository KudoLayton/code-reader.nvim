local M = {}

local function split_lines(text)
  text = (text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  local lines = {}
  if text == "" then
    return lines
  end

  text = text .. "\n"
  for line in text:gmatch("(.-)\n") do
    table.insert(lines, line)
  end
  return lines
end

local function strip_prefix(path)
  if not path or path == "/dev/null" then
    return nil
  end
  return (path:gsub("^a/", ""):gsub("^b/", ""))
end

local function parse_range(start_text, count_text)
  local start_line = tonumber(start_text)
  local count = tonumber(count_text) or 1
  local end_line = start_line + count - 1
  if count == 0 then
    end_line = start_line
  end
  return start_line, count, end_line
end

local function finish_file(doc, file)
  if not file then
    return
  end
  file.hunk_by_id = {}
  file.changed_lines = 0
  for index, hunk in ipairs(file.hunks) do
    hunk.index = index
    hunk.id = "H" .. tostring(index)
    file.hunk_by_id[hunk.id] = hunk
    file.changed_lines = file.changed_lines + hunk.changed_lines
  end
  file.supported = #file.hunks > 0
  doc.total_changed_lines = doc.total_changed_lines + file.changed_lines
  table.insert(doc.files, file)
  if file.path then
    doc.file_by_path[file.path] = file
  end
end

function M.parse(text)
  local doc = {
    files = {},
    file_by_path = {},
    total_changed_lines = 0,
  }
  local current_file = nil
  local current_hunk = nil

  for _, line in ipairs(split_lines(text)) do
    local old_file = line:match("^%-%-%-%s+(.+)$")
    if old_file then
      finish_file(doc, current_file)
      current_file = {
        old_path = strip_prefix(old_file:match("^(%S+)")),
        new_path = nil,
        path = nil,
        hunks = {},
      }
      current_hunk = nil
    else
      local new_file = line:match("^%+%+%+%s+(.+)$")
      if new_file and current_file then
        current_file.new_path = strip_prefix(new_file:match("^(%S+)"))
        current_file.path = current_file.new_path or current_file.old_path
      else
        local old_start, old_count, new_start, new_count =
          line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
        if old_start and current_file then
          local parsed_old_start, parsed_old_count, old_end = parse_range(old_start, old_count)
          local parsed_new_start, parsed_new_count, new_end = parse_range(new_start, new_count)
          current_hunk = {
            old_start = parsed_old_start,
            old_count = parsed_old_count,
            old_end = old_end,
            new_start = parsed_new_start,
            new_count = parsed_new_count,
            new_end = new_end,
            changed_lines = 0,
            lines = {},
          }
          table.insert(current_file.hunks, current_hunk)
        elseif current_hunk and line:sub(1, 1) ~= "\\" then
          local prefix = line:sub(1, 1)
          local content = line:sub(2)
          if prefix == " " then
            table.insert(current_hunk.lines, { kind = "context", text = content })
          elseif prefix == "-" then
            table.insert(current_hunk.lines, { kind = "delete", text = content })
            current_hunk.changed_lines = current_hunk.changed_lines + 1
          elseif prefix == "+" then
            table.insert(current_hunk.lines, { kind = "add", text = content })
            current_hunk.changed_lines = current_hunk.changed_lines + 1
          end
        end
      end
    end
  end

  finish_file(doc, current_file)
  return doc
end

local function hunk_before_lines(hunk)
  local lines = {}
  for _, entry in ipairs(hunk.lines or {}) do
    if entry.kind == "context" or entry.kind == "delete" then
      table.insert(lines, entry.text)
    end
  end
  return lines
end

local function hunk_after_lines(hunk)
  local lines = {}
  for _, entry in ipairs(hunk.lines or {}) do
    if entry.kind == "context" or entry.kind == "add" then
      table.insert(lines, entry.text)
    end
  end
  return lines
end

local function matches_at(lines, start_line, expected)
  if start_line < 1 or start_line + #expected - 1 > #lines then
    return false
  end
  for index, expected_line in ipairs(expected) do
    if lines[start_line + index - 1] ~= expected_line then
      return false
    end
  end
  return true
end

local function replace_at(lines, start_line, remove_count, replacement)
  local result = {}
  for index = 1, start_line - 1 do
    table.insert(result, lines[index])
  end
  for _, line in ipairs(replacement) do
    table.insert(result, line)
  end
  for index = start_line + remove_count, #lines do
    table.insert(result, lines[index])
  end
  return result
end

local function apply_hunk(hunk, current_lines, direction)
  local result = {}
  for _, line in ipairs(current_lines or {}) do
    table.insert(result, line)
  end

  local expected = direction == "forward" and hunk_before_lines(hunk) or hunk_after_lines(hunk)
  local replacement = direction == "forward" and hunk_after_lines(hunk) or hunk_before_lines(hunk)
  local start_line = direction == "forward" and hunk.old_start or hunk.new_start
  if not matches_at(result, start_line, expected) then
    return nil
  end
  return replace_at(result, start_line, #expected, replacement)
end

local function apply_all(file, current_lines, direction)
  local result = {}
  for _, line in ipairs(current_lines or {}) do
    table.insert(result, line)
  end

  local offset = 0
  for _, hunk in ipairs(file.hunks or {}) do
    local expected = direction == "forward" and hunk_before_lines(hunk) or hunk_after_lines(hunk)
    local replacement = direction == "forward" and hunk_after_lines(hunk) or hunk_before_lines(hunk)
    local base_start = direction == "forward" and hunk.old_start or hunk.new_start
    local start_line = base_start + offset
    if not matches_at(result, start_line, expected) then
      return nil
    end
    result = replace_at(result, start_line, #expected, replacement)
    offset = offset + #replacement - #expected
  end

  return result
end

local function count_matching_hunks(file, current_lines)
  local count = 0
  for _, hunk in ipairs(file.hunks or {}) do
    if matches_at(current_lines, hunk.old_start, hunk_before_lines(hunk))
      or matches_at(current_lines, hunk.new_start, hunk_after_lines(hunk))
    then
      count = count + 1
    end
  end
  return count
end

function M.analyze_hunk(file, hunk, current_lines)
  current_lines = current_lines or {}
  if not file or not hunk then
    return { status = "missing", before_lines = current_lines, after_lines = current_lines }
  end

  local after_lines = apply_hunk(hunk, current_lines, "forward")
  if after_lines then
    return {
      status = "applies",
      before_lines = current_lines,
      after_lines = after_lines,
    }
  end

  local before_lines = apply_hunk(hunk, current_lines, "reverse")
  if before_lines then
    return {
      status = "already-applied",
      before_lines = before_lines,
      after_lines = current_lines,
    }
  end

  return {
    status = "stale",
    before_lines = current_lines,
    after_lines = current_lines,
  }
end

function M.analyze_file(file, current_lines)
  current_lines = current_lines or {}
  if not file or #(file.hunks or {}) == 0 then
    return { status = "unsupported", before_lines = current_lines, after_lines = current_lines }
  end

  local after_lines = apply_all(file, current_lines, "forward")
  if after_lines then
    return {
      status = "applies",
      before_lines = current_lines,
      after_lines = after_lines,
    }
  end

  local before_lines = apply_all(file, current_lines, "reverse")
  if before_lines then
    return {
      status = "already-applied",
      before_lines = before_lines,
      after_lines = current_lines,
    }
  end

  local matching_hunks = count_matching_hunks(file, current_lines)
  if matching_hunks > 0 then
    return {
      status = "partial",
      matching_hunks = matching_hunks,
      before_lines = current_lines,
      after_lines = current_lines,
    }
  end

  return {
    status = "stale",
    matching_hunks = 0,
    before_lines = current_lines,
    after_lines = current_lines,
  }
end

function M.hunk_sides(hunk)
  local before_lines = {}
  local after_lines = {}
  for _, entry in ipairs(hunk.lines or {}) do
    if entry.kind == "context" then
      table.insert(before_lines, entry.text)
      table.insert(after_lines, entry.text)
    elseif entry.kind == "delete" then
      table.insert(before_lines, entry.text)
      table.insert(after_lines, "")
    elseif entry.kind == "add" then
      table.insert(before_lines, "")
      table.insert(after_lines, entry.text)
    end
  end
  return before_lines, after_lines
end

function M.hunk_ref_label(file, hunk)
  if not file or not hunk then
    return "none"
  end
  return string.format(
    "Before: `%s#L%d-L%d`  After: `%s#L%d-L%d`",
    file.path,
    hunk.old_start,
    hunk.old_end,
    file.path,
    hunk.new_start,
    hunk.new_end
  )
end

function M.diff_ref_label(diff_ref)
  if not diff_ref then
    return "none"
  end
  local label = diff_ref.path .. "#" .. diff_ref.hunk_id
  if diff_ref.side then
    label = label .. "@" .. diff_ref.side
    if diff_ref.padding then
      label = label .. ":padding=" .. tostring(diff_ref.padding)
    elseif diff_ref.start_bound and diff_ref.end_bound then
      local function bound_text(bound)
        if bound.mode == "relative" then
          local sign = bound.value >= 0 and "+" or ""
          return "L(" .. sign .. tostring(bound.value) .. ")"
        end
        return "L" .. tostring(bound.value)
      end
      label = label .. ":" .. bound_text(diff_ref.start_bound) .. "-" .. bound_text(diff_ref.end_bound)
    end
  end
  return label
end

function M.range_ref_label(file, hunk, diff_ref)
  if not (file and hunk and diff_ref and diff_ref.side) then
    return M.hunk_ref_label(file, hunk)
  end
  local render = require("code_reader.diff_render")
  local range = render.resolve_hunk_range(hunk, diff_ref.side, diff_ref)
  if not range then
    return M.hunk_ref_label(file, hunk)
  end
  local prefix = diff_ref.side == "old" and "Before" or "After"
  return string.format("%s: `%s#L%d-L%d`", prefix, file.path, range.start_line, range.end_line)
end

return M
