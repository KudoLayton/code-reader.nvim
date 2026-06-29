local M = {}

M.namespace = vim.api.nvim_create_namespace("code-reader-syntax")
M.priority = 100

local extension_filetypes = {
  c = "c",
  cpp = "cpp",
  go = "go",
  h = "c",
  hpp = "cpp",
  js = "javascript",
  jsx = "javascriptreact",
  lua = "lua",
  py = "python",
  rs = "rust",
  ts = "typescript",
  tsx = "typescriptreact",
}

local function filetype_for_path(path)
  if vim.filetype and vim.filetype.match then
    local ok, filetype = pcall(vim.filetype.match, { filename = path })
    if ok and filetype and filetype ~= "" then
      return filetype
    end
  end

  local extension = path and path:match("%.([^.\\/]*)$")
  return extension and extension_filetypes[extension]
end

local function language_for_path(path)
  local filetype = filetype_for_path(path)
  if not filetype or filetype == "" then
    return nil
  end

  if vim.treesitter.language and vim.treesitter.language.get_lang then
    local language = vim.treesitter.language.get_lang(filetype) or filetype
    if vim.treesitter.language.inspect then
      local ok = pcall(vim.treesitter.language.inspect, language)
      if not ok then
        return nil
      end
    end
    return language
  end

  return filetype
end

local function highlight_lines(buf, language, lines, line_map, col_offset)
  local text = table.concat(lines, "\n")
  if text == "" then
    return 0
  end

  local parser_ok, parser = pcall(vim.treesitter.get_string_parser, text, language)
  if not parser_ok or not parser then
    return 0
  end

  local trees = parser:parse(true)
  if not trees or #trees == 0 then
    return 0
  end

  local count = 0
  parser:for_each_tree(function(tree, language_tree)
    local tree_language = language_tree:lang()
    local query = vim.treesitter.query.get(tree_language, "highlights")
    if not query then
      return
    end

    for id, node in query:iter_captures(tree:root(), text) do
      local capture = query.captures[id]
      if capture ~= "spell" and capture ~= "nospell" then
        local start_row, start_col, end_row, end_col = node:range()
        local buf_start = line_map[start_row]
        local buf_end = line_map[end_row] or buf_start
        if buf_start and buf_end then
          pcall(vim.api.nvim_buf_set_extmark, buf, M.namespace, buf_start, col_offset + start_col, {
            end_row = buf_end,
            end_col = col_offset + end_col,
            hl_group = "@" .. capture .. "." .. tree_language,
            priority = M.priority,
          })
          count = count + 1
        end
      end
    end
  end)

  return count
end

local function collect_side_lines(rows, side)
  local lines = {}
  local line_map = {}

  for index, row in ipairs(rows or {}) do
    local cell = row[side]
    if cell and cell.kind ~= "blank" then
      line_map[#lines] = index - 1
      table.insert(lines, cell.text or "")
    end
  end

  return lines, line_map
end

function M.highlight_diff(buf, rows, side, path, col_offset)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return 0
  end

  vim.api.nvim_buf_clear_namespace(buf, M.namespace, 0, -1)

  local language = language_for_path(path)
  if not language then
    return 0
  end

  local lines, line_map = collect_side_lines(rows, side)
  return highlight_lines(buf, language, lines, line_map, col_offset or 0)
end

return M
