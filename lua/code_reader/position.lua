local M = {}

local function string_ids(value)
  local result = {}
  if type(value) ~= "table" then
    return result
  end
  for _, item in ipairs(value) do
    if type(item) == "string" and item ~= "" then
      table.insert(result, item)
    end
  end
  return result
end

local function display_node(map, id)
  local node = map.nodes[id]
  return tostring(node and (node.label or node.id) or id)
end

local function display_edge(map, id)
  local edge = map.edges[id]
  return tostring(edge and (edge.label or edge.id) or id)
end

local function execution_maps(doc)
  local maps = {}
  for _, step in ipairs(doc.steps or {}) do
    for _, evidence in ipairs(step.evidence or {}) do
      if evidence.kind == "sketch" and evidence.purpose == "execution-map" and type(evidence.text_model) == "table" then
        local map = { id = evidence.id, nodes = {}, edges = {}, edge_list = {} }
        for _, node in ipairs(evidence.text_model.nodes or {}) do
          if type(node) == "table" and type(node.id) == "string" then
            map.nodes[node.id] = node
          end
        end
        for _, edge in ipairs(evidence.text_model.edges or {}) do
          if type(edge) == "table" and type(edge.id) == "string" then
            map.edges[edge.id] = edge
            table.insert(map.edge_list, edge)
          end
        end
        table.insert(maps, map)
      end
    end
  end
  return maps
end

local function resolve_map(maps, anchor, stage_id)
  if type(anchor) == "table" then
    local map_id = tonumber(anchor.map)
    for _, map in ipairs(maps) do
      if map.id == map_id then
        return map, string_ids(anchor.nodes), string_ids(anchor.edges)
      end
    end
    return nil
  end
  if #maps == 1 and maps[1].nodes[stage_id] then
    return maps[1], { stage_id }, {}
  end
end

local function unique(items)
  local result = {}
  local seen = {}
  for _, item in ipairs(items) do
    if item and not seen[item] then
      table.insert(result, item)
      seen[item] = true
    end
  end
  return result
end

function M.resolve(doc, step)
  if not doc or not step or step.kind == "front_page" then
    return nil
  end
  local maps = execution_maps(doc)
  if #maps == 0 then
    return nil
  end
  local anchor = step.map_anchor or (step.metadata and step.metadata.map_anchor) or nil
  local map, selected_node_ids, selected_edge_ids = resolve_map(maps, anchor, step.id)
  if not map then
    return nil
  end
  local focus_nodes = {}
  for _, node_id in ipairs(selected_node_ids) do
    focus_nodes[node_id] = true
  end
  local selected_edges = {}
  for _, edge_id in ipairs(selected_edge_ids) do
    local edge = map.edges[edge_id]
    if edge then
      selected_edges[edge_id] = true
      focus_nodes[edge.from] = true
      focus_nodes[edge.to] = true
    end
  end
  local incoming = {}
  local outgoing = {}
  for _, edge in ipairs(map.edge_list) do
    if not selected_edges[edge.id] and focus_nodes[edge.to] and not focus_nodes[edge.from] then
      table.insert(incoming, edge)
    end
    if not selected_edges[edge.id] and focus_nodes[edge.from] and not focus_nodes[edge.to] then
      table.insert(outgoing, edge)
    end
  end
  return {
    map = map,
    node_ids = unique(selected_node_ids),
    edge_ids = unique(selected_edge_ids),
    focus_nodes = focus_nodes,
    incoming = incoming,
    outgoing = outgoing,
  }
end

function M.lines(doc, step)
  local position = M.resolve(doc, step)
  if not position then
    return {}
  end
  local current = {}
  for _, node_id in ipairs(position.node_ids) do
    table.insert(current, display_node(position.map, node_id))
  end
  for _, edge_id in ipairs(position.edge_ids) do
    table.insert(current, display_edge(position.map, edge_id))
  end
  if #current == 0 then
    return {}
  end
  local incoming = {}
  for _, edge in ipairs(position.incoming) do
    table.insert(incoming, display_node(position.map, edge.from) .. " ── " .. display_edge(position.map, edge.id))
  end
  local outgoing = {}
  for _, edge in ipairs(position.outgoing) do
    table.insert(outgoing, display_edge(position.map, edge.id) .. " ──▶ " .. display_node(position.map, edge.to))
  end
  local lines = {
    "",
    "## Execution position",
    "",
    "Current explanation scope: " .. table.concat(current, " · "),
    "",
  }
  if #incoming > 0 then
    table.insert(lines, "  " .. table.concat(incoming, " · "))
    table.insert(lines, "                  │")
  end
  table.insert(lines, "  ● [ " .. table.concat(current, " · ") .. " ]")
  if #outgoing > 0 then
    table.insert(lines, "                  └─▶ " .. table.concat(outgoing, " · "))
  end
  return lines
end

return M
