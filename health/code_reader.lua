local M = {}

function M.check()
  local ok, code_reader = pcall(require, "code_reader")
  local opts = {}
  if ok and code_reader.state then
    local state = code_reader.state()
    opts.options = state.options
    opts.mermaid = state.options and state.options.mermaid or nil
    opts.syntax_paths = {}
    for _, file in ipairs((state.diff and state.diff.files) or {}) do
      table.insert(opts.syntax_paths, file.path)
    end
  end

  require("code_reader.health").check(opts)
end

return M
