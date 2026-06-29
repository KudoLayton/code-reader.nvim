package.path = table.concat({
  "lua/?.lua",
  "lua/?/init.lua",
  package.path,
}, ";")

local source = require("code_reader.source")

local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)), 2)
  end
end

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local file = tmp .. "/sample.lua"
vim.fn.writefile({
  "local a = 1",
  "local b = 2",
  "return a + b",
}, file)

local hash = source.range_hash(file, 1, 2)
eq(type(hash), "string", "hash type")
eq(#hash, 64, "hash length")

local ok_status = source.status({
  path = "sample.lua",
  start_line = 1,
  end_line = 2,
  expected_hash = hash,
}, {
  root = tmp,
})
eq(ok_status.kind, "fresh", "fresh status")

local stale_status = source.status({
  path = "sample.lua",
  start_line = 1,
  end_line = 2,
  expected_hash = string.rep("0", 64),
}, {
  root = tmp,
})
eq(stale_status.kind, "stale", "stale status")

local missing_status = source.status({
  path = "missing.lua",
  start_line = 1,
  end_line = 1,
}, {
  root = tmp,
})
eq(missing_status.kind, "missing", "missing status")

print("nvim_spec: ok")
