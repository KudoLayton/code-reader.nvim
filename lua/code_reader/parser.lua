local M = {}

local FRONT_PAGE_MARKER = "<!-- code-reader: front-page -->"

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

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

local function parse_scalar(value)
  value = trim(value or "")
  local quoted = value:match('^"(.*)"$') or value:match("^'(.*)'$")
  if quoted ~= nil then
    return quoted
  end
  return value
end

local function parse_frontmatter(lines)
  local frontmatter = {}
  if trim(lines[1] or "") ~= "---" then
    return frontmatter, 1
  end

  local index = 2
  while index <= #lines do
    local line = lines[index]
    if trim(line) == "---" then
      return frontmatter, index + 1
    end

    local key, value = line:match("^%s*([%w_.-]+)%s*:%s*(.-)%s*$")
    if key then
      frontmatter[key] = parse_scalar(value)
    end
    index = index + 1
  end

  return frontmatter, index
end

local function split_sections(lines, start_index)
  local sections = {}
  local current = {}

  local function flush()
    local has_content = false
    for _, line in ipairs(current) do
      if trim(line) ~= "" then
        has_content = true
        break
      end
    end

    if has_content then
      table.insert(sections, current)
    end
    current = {}
  end

  for index = start_index, #lines do
    local line = lines[index]
    if trim(line) == "---" then
      flush()
    else
      table.insert(current, line)
    end
  end

  flush()
  return sections
end

local function parse_heading(lines)
  for index, line in ipairs(lines) do
    local hashes, text = line:match("^(#+)%s+(.+)%s*$")
    if hashes then
      text = trim(text:gsub("%s+#%s*$", ""))
      local id, title = text:match("^([0-9][0-9%.]*)%s+(.+)$")
      if id then
        id = id:gsub("%.$", "")
        title = trim(title)
      else
        title = text
      end

      return {
        index = index,
        level = #hashes,
        id = id,
        title = title,
      }
    end
  end
end

local function add_source(sources, seen, path, start_line, end_line, expected_hash)
  if not path or not start_line then
    return
  end

  path = path:gsub("\\", "/")
  start_line = tonumber(start_line)
  end_line = tonumber(end_line) or start_line

  if not start_line or start_line < 1 then
    return
  end
  if end_line < start_line then
    end_line = start_line
  end

  local key = table.concat({ path, start_line, end_line }, ":")
  if seen[key] then
    return
  end

  table.insert(sources, {
    path = path,
    start_line = start_line,
    end_line = end_line,
    expected_hash = expected_hash,
  })
  seen[key] = true
end

local function parse_sources(lines)
  local sources = {}
  local seen = {}

  for _, line in ipairs(lines) do
    local masked = line

    for path, start_line, end_line, expected_hash in line:gmatch("([%w%._%-/%\\]+)#L(%d+)%-L(%d+)@sha256:([a-fA-F0-9]+)") do
      add_source(sources, seen, path, start_line, end_line, expected_hash:lower())
    end
    masked = masked:gsub("[%w%._%-/%\\]+#L%d+%-L%d+@sha256:[a-fA-F0-9]+", "")

    for path, start_line, end_line in line:gmatch("([%w%._%-/%\\]+)#L(%d+)%-L(%d+)") do
      add_source(sources, seen, path, start_line, end_line)
    end
    masked = masked:gsub("[%w%._%-/%\\]+#L%d+%-L%d+", "")

    for path, start_line, end_line, expected_hash in line:gmatch("([%w%._%-/%\\]+)#L(%d+)%-(%d+)@sha256:([a-fA-F0-9]+)") do
      add_source(sources, seen, path, start_line, end_line, expected_hash:lower())
    end
    masked = masked:gsub("[%w%._%-/%\\]+#L%d+%-%d+@sha256:[a-fA-F0-9]+", "")

    for path, start_line, end_line in line:gmatch("([%w%._%-/%\\]+)#L(%d+)%-(%d+)") do
      add_source(sources, seen, path, start_line, end_line)
    end
    masked = masked:gsub("[%w%._%-/%\\]+#L%d+%-%d+", "")

    for path, start_line, expected_hash in masked:gmatch("([%w%._%-/%\\]+)#L(%d+)@sha256:([a-fA-F0-9]+)") do
      add_source(sources, seen, path, start_line, start_line, expected_hash:lower())
    end
    masked = masked:gsub("[%w%._%-/%\\]+#L%d+@sha256:[a-fA-F0-9]+", "")

    for path, start_line in masked:gmatch("([%w%._%-/%\\]+)#L(%d+)") do
      add_source(sources, seen, path, start_line, start_line)
    end
  end

  return sources
end

local function normalize_diff_side(side)
  side = side and side:lower() or nil
  if side == "a" then
    return "old"
  end
  if side == "b" then
    return "new"
  end
  if side == "old" or side == "new" then
    return side
  end
  return nil
end

local function parse_diff_bound(value)
  value = value or ""
  local parenthesized = value:match("^%(([%+%-]?%d+)%)$")
  value = parenthesized or value
  local number = tonumber(value)
  if not number then
    return nil
  end
  if value:sub(1, 1) == "+" or value:sub(1, 1) == "-" then
    return { mode = "relative", value = number }
  end
  return { mode = "absolute", value = number }
end

local function parse_diff_range(value)
  if not value then
    return nil
  end

  local body = value:match("^L(.+)$")
  if not body then
    return nil, nil
  end

  local start_text, end_text = body:match("^(%b())%-L(.+)$")
  if not start_text then
    start_text, end_text = body:match("^([%+%-]%d+)%-L(.+)$")
  end
  if not start_text then
    start_text, end_text = body:match("^(%d+)%-L(.+)$")
  end
  if not start_text then
    local bound = parse_diff_bound(body)
    return bound, bound
  end

  return parse_diff_bound(start_text), parse_diff_bound(end_text)
end

local function parse_diff_modifier(ref, side, value)
  local normalized_side = normalize_diff_side(side)
  if not normalized_side then
    return
  end

  ref.side = normalized_side
  local padding = value and (value:match("^padding=(%d+)$") or value:match("^pad=(%d+)$"))
  if padding then
    ref.padding = tonumber(padding)
    return
  end

  local start_bound, end_bound = parse_diff_range(value)
  if start_bound and end_bound then
    ref.start_bound = start_bound
    ref.end_bound = end_bound
  end
end

local function diff_ref_key(ref)
  local parts = { ref.path, ref.hunk_id, ref.side or "" }
  if ref.padding then
    table.insert(parts, "padding=" .. tostring(ref.padding))
  end
  if ref.start_bound then
    table.insert(parts, ref.start_bound.mode .. tostring(ref.start_bound.value))
  end
  if ref.end_bound then
    table.insert(parts, ref.end_bound.mode .. tostring(ref.end_bound.value))
  end
  return table.concat(parts, "#")
end

local function add_diff_ref(diff_refs, seen, path, hunk_id, side, modifier)
  if not path or not hunk_id then
    return
  end

  path = path:gsub("\\", "/")
  hunk_id = hunk_id:upper()
  local ref = {
    path = path,
    hunk_id = hunk_id,
  }
  if side and modifier then
    parse_diff_modifier(ref, side, modifier)
  end
  local key = diff_ref_key(ref)
  if seen[key] then
    return
  end

  table.insert(diff_refs, ref)
  seen[key] = true
end

local function parse_diff_refs(lines)
  local diff_refs = {}
  local seen = {}

  for _, line in ipairs(lines) do
    for path, hunk_id, side, modifier in line:gmatch("([%w%._%-/%\\]+)#(H%d+)@([%w]+):([^%s`%]]+)") do
      add_diff_ref(diff_refs, seen, path, hunk_id, side, modifier)
    end
    local masked = line:gsub("[%w%._%-/%\\]+#H%d+@[%w]+:[^%s`%]]+", "")

    for path, hunk_id in masked:gmatch("([%w%._%-/%\\]+)#(H%d+)") do
      add_diff_ref(diff_refs, seen, path, hunk_id)
    end
    for path, hunk_number in masked:gmatch("([%w%._%-/%\\]+)#h(%d+)") do
      add_diff_ref(diff_refs, seen, path, "H" .. hunk_number)
    end
  end

  return diff_refs
end

local function count_numeric_depth(id)
  if not id or id == "" then
    return 1
  end

  local depth = 1
  for _ in id:gmatch("%.") do
    depth = depth + 1
  end
  return depth
end

local function section_content(lines, heading_index)
  local content = {}
  for index, line in ipairs(lines) do
    if index ~= heading_index then
      table.insert(content, line)
    end
  end
  return table.concat(content, "\n"):gsub("^%s*\n", ""):gsub("\n%s*$", "")
end

local function first_non_empty_index(lines)
  for index, line in ipairs(lines) do
    if trim(line) ~= "" then
      return index
    end
  end
end

local function without_line(lines, remove_index)
  local result = {}
  for index, line in ipairs(lines) do
    if index ~= remove_index then
      table.insert(result, line)
    end
  end
  return result
end

local function parse_step(lines, index)
  local marker_index = index == 1 and first_non_empty_index(lines) or nil
  local is_front_page = marker_index and trim(lines[marker_index]) == FRONT_PAGE_MARKER
  local step_lines = is_front_page and without_line(lines, marker_index) or lines
  local heading = parse_heading(step_lines)
  local id = heading and heading.id or tostring(index)
  local title = heading and heading.title or ("Step " .. tostring(index))
  local depth = heading and heading.level or count_numeric_depth(id)

  if is_front_page then
    id = "front"
    title = heading and heading.title or "Front Page"
    depth = heading and heading.level or 1
  end

  if not id or id == "" then
    id = tostring(index)
  end

  return {
    index = index,
    kind = is_front_page and "front_page" or "step",
    id = id,
    title = title,
    depth = depth,
    body = table.concat(step_lines, "\n"),
    content = section_content(step_lines, heading and heading.index),
    sources = parse_sources(step_lines),
    diff_refs = parse_diff_refs(step_lines),
  }
end

function M.parse(text, opts)
  opts = opts or {}
  local lines = split_lines(text)
  local frontmatter, start_index = parse_frontmatter(lines)
  local sections = split_sections(lines, start_index)
  local steps = {}
  local step_by_id = {}
  local front_page_index = nil

  for index, section in ipairs(sections) do
    local step = parse_step(section, index)
    table.insert(steps, step)
    step_by_id[step.id] = index
    if step.kind == "front_page" then
      front_page_index = index
    end
  end

  return {
    path = opts.path,
    frontmatter = frontmatter,
    steps = steps,
    step_by_id = step_by_id,
    front_page_index = front_page_index,
  }
end

return M
