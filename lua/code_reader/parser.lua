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

local function parse_yaml_scalar(value)
  local scalar = parse_scalar(value)
  if scalar == "true" then
    return true
  end
  if scalar == "false" then
    return false
  end
  local number = tonumber(scalar)
  return number or scalar
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

local function indentation(line)
  local spaces = #(line:match("^(%s*)") or "")
  if spaces % 2 ~= 0 then
    return nil
  end
  return math.floor(spaces / 2)
end

local function yaml_tokens(lines)
  local tokens = {}
  for _, item in ipairs(lines) do
    if trim(item.text) ~= "" then
      local indent = indentation(item.text)
      if not indent then
        return nil, "YAML indentation must use multiples of two spaces"
      end
      table.insert(tokens, {
        indent = indent,
        text = trim(item.text),
        line = item.line,
      })
    end
  end
  return tokens
end

local parse_yaml_block

local function merge_map(target, source)
  for key, value in pairs(source or {}) do
    target[key] = value
  end
  return target
end

local function parse_yaml_map(tokens, position, indent)
  local result = {}
  while position <= #tokens do
    local token = tokens[position]
    if token.indent < indent or token.indent ~= indent or token.text:match("^%- ") then
      break
    end
    local key, value = token.text:match("^([%w_-]+):%s*(.-)%s*$")
    if not key then
      return nil, position, "invalid YAML mapping at line " .. tostring(token.line)
    end
    position = position + 1
    if value ~= "" then
      result[key] = parse_yaml_scalar(value)
    elseif position <= #tokens and tokens[position].indent > indent then
      local child, next_position, err = parse_yaml_block(tokens, position, tokens[position].indent)
      if not child then
        return nil, next_position, err
      end
      result[key] = child
      position = next_position
    else
      result[key] = {}
    end
  end
  return result, position
end

local function parse_yaml_list(tokens, position, indent)
  local result = {}
  while position <= #tokens do
    local token = tokens[position]
    if token.indent ~= indent or not token.text:match("^%- ") then
      break
    end
    local value = trim(token.text:sub(3))
    position = position + 1
    if value == "" then
      if position > #tokens or tokens[position].indent <= indent then
        return nil, position, "list item requires a value at line " .. tostring(token.line)
      end
      local child, next_position, err = parse_yaml_block(tokens, position, tokens[position].indent)
      if not child then
        return nil, next_position, err
      end
      table.insert(result, child)
      position = next_position
    else
      local key, scalar = value:match("^([%w_-]+):%s*(.-)%s*$")
      if key then
        local item = {}
        if scalar ~= "" then
          item[key] = parse_yaml_scalar(scalar)
        elseif position <= #tokens and tokens[position].indent > indent then
          local child, next_position, err = parse_yaml_block(tokens, position, tokens[position].indent)
          if not child then
            return nil, next_position, err
          end
          item[key] = child
          position = next_position
        else
          item[key] = {}
        end
        if position <= #tokens and tokens[position].indent > indent then
          local child, next_position, err = parse_yaml_map(tokens, position, tokens[position].indent)
          if not child then
            return nil, next_position, err
          end
          merge_map(item, child)
          position = next_position
        end
        table.insert(result, item)
      else
        table.insert(result, parse_yaml_scalar(value))
      end
    end
  end
  return result, position
end

parse_yaml_block = function(tokens, position, indent)
  if tokens[position] and tokens[position].text:match("^%- ") then
    return parse_yaml_list(tokens, position, indent)
  end
  return parse_yaml_map(tokens, position, indent)
end

local function parse_restricted_yaml(lines)
  local tokens, token_err = yaml_tokens(lines)
  if not tokens then
    return nil, token_err
  end
  if #tokens == 0 then
    return {}, nil
  end
  local result, position, err = parse_yaml_block(tokens, 1, tokens[1].indent)
  if not result then
    return nil, err
  end
  if position <= #tokens then
    return nil, "unexpected YAML token at line " .. tostring(tokens[position].line)
  end
  return result, nil
end

local function extract_v2_metadata(lines)
  local start_index = nil
  for index, item in ipairs(lines) do
    if trim(item.text) == "```code-reader" then
      start_index = index
      break
    end
  end
  if not start_index then
    return {}, lines, nil
  end
  local end_index = nil
  for index = start_index + 1, #lines do
    if trim(lines[index].text) == "```" then
      end_index = index
      break
    end
  end
  if not end_index then
    return {}, lines, "code-reader metadata fence is not closed"
  end
  local metadata_lines = {}
  for index = start_index + 1, end_index - 1 do
    table.insert(metadata_lines, lines[index])
  end
  local metadata, err = parse_restricted_yaml(metadata_lines)
  if err then
    return {}, lines, err
  end
  local remaining = {}
  for index, item in ipairs(lines) do
    if index < start_index or index > end_index then
      table.insert(remaining, item)
    end
  end
  return metadata, remaining, nil
end

local function split_sections(lines, start_index)
  local sections = {}
  local current = {}
  local current_start = nil

  local function flush()
    local has_content = false
    for _, item in ipairs(current) do
      local line = item.text
      if trim(line) ~= "" then
        has_content = true
        break
      end
    end

    if has_content then
      table.insert(sections, {
        lines = current,
        start_line = current_start,
      })
    end
    current = {}
    current_start = nil
  end

  for index = start_index, #lines do
    local line = lines[index]
    if trim(line) == "---" then
      flush()
    else
      current_start = current_start or index
      table.insert(current, {
        text = line,
        line = index,
      })
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
    if not trim(line):match("^Cursor:%s*") then
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
  end

  return sources
end

local function parse_cursor(lines)
  for _, line in ipairs(lines) do
    if trim(line):match("^Cursor:%s*") then
      local path, line_number = line:match("([%w%._%-/%\\]+)#L(%d+)")
      if path and line_number then
        return {
          path = path:gsub("\\", "/"),
          line = tonumber(line_number),
        }
      end
    end
  end
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

local function parse_single_source(value)
  local refs = parse_sources({ tostring(value or "") })
  return refs[1]
end

local function parse_single_diff(value)
  local refs = parse_diff_refs({ tostring(value or "") })
  return refs[1]
end

local function normalize_evidence(metadata)
  local evidence = {}
  local by_id = {}
  for _, item in ipairs(metadata.evidence or {}) do
    local id = tonumber(item.id)
    local kind = item.kind and tostring(item.kind):lower() or nil
    if id and kind and item.target then
      local normalized = {
        id = id,
        kind = kind,
        target = tostring(item.target),
        claim = item.claim and tostring(item.claim) or "",
        purpose = item.purpose and tostring(item.purpose) or nil,
        coverage = item.coverage,
        text_model = item.text_model,
      }
      if kind == "source" then
        normalized.source = parse_single_source(item.target)
        local cursor = parse_single_source(item.cursor)
        if normalized.source and cursor and cursor.path == normalized.source.path then
          normalized.source.cursor_line = cursor.start_line
        end
      elseif kind == "diff" then
        normalized.diff_ref = parse_single_diff(item.target)
      elseif kind == "sketch" then
        normalized.path = tostring(item.target):gsub("\\", "/")
        normalized.editable_target = item.editable_target and tostring(item.editable_target) or nil
        normalized.editable_path = normalized.editable_target and normalized.editable_target:gsub("\\", "/") or nil
      end
      table.insert(evidence, normalized)
      by_id[id] = normalized
    end
  end
  return evidence, by_id
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

local function is_metadata_directive(text)
  local value = trim(text)
  return value:match("^Source:%s*") or value:match("^Diff:%s*") or value:match("^Cursor:%s*")
end

local function section_content(lines, heading_index)
  local content = {}
  local line_map = {}
  for index, item in ipairs(lines) do
    if index ~= heading_index and not is_metadata_directive(item.text) then
      table.insert(content, item.text)
      table.insert(line_map, item.line)
    end
  end

  local first = 1
  while first <= #content and trim(content[first]) == "" do
    first = first + 1
  end
  local last = #content
  while last >= first and trim(content[last]) == "" do
    last = last - 1
  end
  if first > last then
    return "", {}
  end

  local trimmed = {}
  local trimmed_map = {}
  for index = first, last do
    table.insert(trimmed, content[index])
    table.insert(trimmed_map, line_map[index])
  end
  return table.concat(trimmed, "\n"), trimmed_map
end

local function first_non_empty_index(lines)
  for index, item in ipairs(lines) do
    if trim(item.text) ~= "" then
      return index
    end
  end
end

local function without_line(lines, remove_index)
  local result = {}
  for index, item in ipairs(lines) do
    if index ~= remove_index then
      table.insert(result, item)
    end
  end
  return result
end

local function item_texts(items)
  local lines = {}
  for _, item in ipairs(items) do
    table.insert(lines, item.text)
  end
  return lines
end

local function parse_step(section, index, is_v2)
  local lines = section.lines or {}
  local marker_index = index == 1 and first_non_empty_index(lines) or nil
  local legacy_front_page = marker_index and trim(lines[marker_index].text) == FRONT_PAGE_MARKER
  local base_lines = legacy_front_page and without_line(lines, marker_index) or lines
  local metadata, step_lines, metadata_error = extract_v2_metadata(base_lines)
  if not is_v2 then
    metadata = {}
    step_lines = base_lines
    metadata_error = nil
  end
  local is_front_page = legacy_front_page or metadata.kind == "overview"
  local step_texts = item_texts(step_lines)
  local heading = parse_heading(step_texts)
  local id = metadata.id and tostring(metadata.id) or (heading and heading.id) or tostring(index)
  local title = heading and heading.title or ("Step " .. tostring(index))
  local depth = heading and heading.level or count_numeric_depth(id)
  local content, content_line_map = section_content(step_lines, heading and heading.index)
  local evidence, evidence_by_id = normalize_evidence(metadata)
  local sources = parse_sources(step_texts)
  local diff_refs = parse_diff_refs(step_texts)
  for _, item in ipairs(evidence) do
    if item.source then
      table.insert(sources, item.source)
    elseif item.diff_ref then
      table.insert(diff_refs, item.diff_ref)
    end
  end
  local cursor = parse_cursor(step_texts)
  local primary_source = sources[1]
  if
    cursor
    and primary_source
    and cursor.path == primary_source.path
    and cursor.line >= primary_source.start_line
    and cursor.line <= primary_source.end_line
  then
    primary_source.cursor_line = cursor.line
  end

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
    body = table.concat(step_texts, "\n"),
    content = content,
    content_line_map = content_line_map,
    heading_line = heading and step_lines[heading.index] and step_lines[heading.index].line or nil,
    start_line = section.start_line,
    end_line = step_lines[#step_lines] and step_lines[#step_lines].line or section.start_line,
    sources = sources,
    diff_refs = diff_refs,
    metadata = metadata,
    map_anchor = metadata.map_anchor,
    metadata_error = metadata_error,
    evidence = evidence,
    evidence_by_id = evidence_by_id,
  }
end

function M.parse(text, opts)
  opts = opts or {}
  local lines = split_lines(text)
  local frontmatter, start_index = parse_frontmatter(lines)
  local is_v2 = tostring(frontmatter.version or "") == "2"
  local sections = split_sections(lines, start_index)
  local steps = {}
  local step_by_id = {}
  local front_page_index = nil

  for index, section in ipairs(sections) do
    local step = parse_step(section, index, is_v2)
    table.insert(steps, step)
    step_by_id[step.id] = index
    if step.kind == "front_page" then
      front_page_index = index
    end
  end

  return {
    path = opts.path,
    frontmatter = frontmatter,
    version_supported = is_v2,
    steps = steps,
    step_by_id = step_by_id,
    front_page_index = front_page_index,
  }
end

return M
