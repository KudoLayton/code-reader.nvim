package.path = table.concat({
  "lua/?.lua",
  "lua/?/init.lua",
  package.path,
}, ";")

local links = require("code_reader.links")

local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)), 2)
  end
end

local function at(line, needle)
  local start_index = line:find(needle, 1, true)
  if not start_index then
    error("needle not found: " .. needle, 2)
  end
  return links.find_at(line, start_index + 1)
end

local internal = at("Continue at [[1.1|Parse request]] after setup.", "[[1.1")
eq(internal.kind, "step", "internal kind")
eq(internal.target, "1.1", "internal target")
eq(internal.label, "Parse request", "internal label")

local simple_internal = at("Continue at [[2]] after setup.", "[[2")
eq(simple_internal.kind, "step", "simple internal kind")
eq(simple_internal.target, "2", "simple internal target")
eq(simple_internal.label, "2", "simple internal label")

local query_line = "[run](<treesitter://src/app.lua?query=(identifier) @code_reader.symbol>)"
local symbol = at(query_line, "run")
eq(symbol.kind, "treesitter", "symbol kind")
eq(symbol.path, "src/app.lua", "symbol path")
eq(symbol.query, "(identifier) @code_reader.symbol", "symbol query")
eq(symbol.label, "run", "symbol label")

local source = at("[parser](src/parser.lua#L5-L12)", "parser")
eq(source, nil, "source link is not an actionable link")

local evidence_line = "The dispatch boundary is [2](code-reader://evidence/2)."
local evidence = at(evidence_line, "[2]")
eq(evidence.kind, "evidence", "evidence link kind")
eq(evidence.id, 2, "evidence link id")
eq(evidence.label, "2", "evidence link label")

local missing_query = at("[bad](<treesitter://src/app.lua>)", "bad")
eq(missing_query.kind, "invalid", "missing query kind")
eq(missing_query.reason, "missing-query", "missing query reason")

print("links_spec: ok")
