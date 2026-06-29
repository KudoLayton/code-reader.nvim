local M = {}

function M.check()
  local ok, code_reader = pcall(require, "code_reader")
  local opts = {}
  if ok and code_reader.state then
    opts.mermaid = code_reader.state().options and code_reader.state().options.mermaid or nil
  end

  require("code_reader.health").check(opts)
end

return M
