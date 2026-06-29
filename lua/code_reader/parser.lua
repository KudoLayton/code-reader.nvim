local M = {}

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

local function parse_step(lines, index)
  local heading = parse_heading(lines)
  local id = heading and heading.id or tostring(index)
  local title = heading and heading.title or ("Step " .. tostring(index))
  local depth = heading and heading.level or count_numeric_depth(id)

  if not id or id == "" then
    id = tostring(index)
  end

  return {
    index = index,
    id = id,
    title = title,
    depth = depth,
    body = table.concat(lines, "\n"),
    content = section_content(lines, heading and heading.index),
    sources = parse_sources(lines),
  }
end

function M.parse(text, opts)
  opts = opts or {}
  local lines = split_lines(text)
  local frontmatter, start_index = parse_frontmatter(lines)
  local sections = split_sections(lines, start_index)
  local steps = {}
  local step_by_id = {}

  for index, section in ipairs(sections) do
    local step = parse_step(section, index)
    table.insert(steps, step)
    step_by_id[step.id] = index
  end

  return {
    path = opts.path,
    frontmatter = frontmatter,
    steps = steps,
    step_by_id = step_by_id,
  }
end

return M
