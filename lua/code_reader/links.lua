local M = {}

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function percent_decode(value)
  value = (value or ""):gsub("+", " ")
  return (value:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

local function parse_step_link(body, start_index, end_index)
  local target, label = body:match("^([^|]+)|(.+)$")
  if target then
    target = trim(target)
    label = trim(label)
  else
    target = trim(body)
    label = target
  end

  if target == "" then
    return nil
  end

  return {
    kind = "step",
    target = target,
    label = label,
    start_col = start_index,
    end_col = end_index,
  }
end

local function parse_query_params(query_string)
  local params = {}
  for part in (query_string or ""):gmatch("[^&]+") do
    local key, value = part:match("^([^=]+)=(.*)$")
    if key then
      params[percent_decode(key)] = percent_decode(value)
    end
  end
  return params
end

local function parse_treesitter_link(label, target, start_index, end_index)
  local rest = target:match("^treesitter://(.+)$")
  if not rest then
    return nil
  end

  local path, query_string = rest:match("^([^?]+)%?(.*)$")
  if not path then
    path = rest
    query_string = ""
  end
  if not path or path == "" then
    return {
      kind = "invalid",
      reason = "missing-path",
      label = label,
      start_col = start_index,
      end_col = end_index,
    }
  end

  local params = parse_query_params(query_string)
  local query = params.query
  if not query or query == "" then
    return {
      kind = "invalid",
      reason = "missing-query",
      label = label,
      path = percent_decode(path),
      start_col = start_index,
      end_col = end_index,
    }
  end

  return {
    kind = "treesitter",
    label = label,
    path = percent_decode(path),
    query = query,
    start_col = start_index,
    end_col = end_index,
  }
end

local function parse_evidence_link(label, target, start_index, end_index)
  local id = target:match("^code%-reader://evidence/(%d+)$")
  if not id then
    return nil
  end
  return {
    kind = "evidence",
    id = tonumber(id),
    label = label,
    start_col = start_index,
    end_col = end_index,
  }
end

local function find_internal_at(line, column)
  local search_from = 1
  while true do
    local start_index = line:find("[[", search_from, true)
    if not start_index then
      return nil
    end

    local end_index = line:find("]]", start_index + 2, true)
    if not end_index then
      return nil
    end

    local close_index = end_index + 1
    if column >= start_index and column <= close_index then
      local body = line:sub(start_index + 2, end_index - 1)
      return parse_step_link(body, start_index, close_index)
    end

    search_from = close_index + 1
  end
end

local function find_label_close(line, open_index)
  local index = open_index + 1
  while index <= #line do
    local char = line:sub(index, index)
    if char == "]" then
      return index
    end
    index = index + 1
  end
end

local function find_markdown_target_close(line, target_start)
  if line:sub(target_start, target_start) == "<" then
    local angle_close = line:find(">", target_start + 1, true)
    if angle_close and line:sub(angle_close + 1, angle_close + 1) == ")" then
      return angle_close + 1, line:sub(target_start + 1, angle_close - 1)
    end
    return nil
  end

  local depth = 0
  local index = target_start
  while index <= #line do
    local char = line:sub(index, index)
    if char == "(" then
      depth = depth + 1
    elseif char == ")" then
      if depth == 0 then
        return index, line:sub(target_start, index - 1)
      end
      depth = depth - 1
    end
    index = index + 1
  end
end

local function find_markdown_at(line, column)
  local search_from = 1
  while true do
    local open_index = line:find("[", search_from, true)
    if not open_index then
      return nil
    end

    if line:sub(open_index + 1, open_index + 1) == "[" then
      search_from = open_index + 2
    else
      local label_close = find_label_close(line, open_index)
      if not label_close then
        return nil
      end

      if line:sub(label_close + 1, label_close + 1) == "(" then
        local target_close, target = find_markdown_target_close(line, label_close + 2)
        if target_close then
          if column >= open_index and column <= target_close then
            local label = line:sub(open_index + 1, label_close - 1)
            return parse_evidence_link(label, target, open_index, target_close)
              or parse_treesitter_link(label, target, open_index, target_close)
          end
          search_from = target_close + 1
        else
          search_from = label_close + 1
        end
      else
        search_from = label_close + 1
      end
    end
  end
end

function M.find_at(line, column)
  if not line or not column then
    return nil
  end

  return find_internal_at(line, column) or find_markdown_at(line, column)
end

return M
