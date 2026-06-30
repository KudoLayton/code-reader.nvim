local M = {}
local log = require("code_reader.log")

M.namespace = vim.api.nvim_create_namespace("code-reader-syntax")
M.priority = 10000

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

function M.filetype_for_path(path)
  return filetype_for_path(path)
end

function M.language_for_filetype(filetype)
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

local function line_col_offset(col_offsets, row, fallback)
  if type(col_offsets) == "table" then
    return col_offsets[row] or fallback or 0
  end
  return col_offsets or fallback or 0
end

local function highlight_lines(buf, language, lines, line_map, col_offsets)
  local text = table.concat(lines, "\n")
  if text == "" then
    return 0
  end

  local parser_ok, parser = pcall(vim.treesitter.get_string_parser, text, language)
  if not parser_ok or not parser then
    return 0, "parser unavailable: " .. tostring(parser)
  end

  local trees = parser:parse(true)
  if not trees or #trees == 0 then
    return 0, "parser returned no tree"
  end

  local count = 0
  local query_missing = false
  parser:for_each_tree(function(tree, language_tree)
    local tree_language = language_tree:lang()
    local query_ok, query = pcall(vim.treesitter.query.get, tree_language, "highlights")
    if not query_ok or not query then
      query_missing = true
      return
    end

    for id, node in query:iter_captures(tree:root(), text) do
      local capture = query.captures[id]
      if capture ~= "spell" and capture ~= "nospell" then
        local start_row, start_col, end_row, end_col = node:range()
        local buf_start = line_map[start_row]
        local buf_end = line_map[end_row] or buf_start
        if buf_start and buf_end then
          local start_offset = line_col_offset(col_offsets, start_row, 0)
          local end_offset = line_col_offset(col_offsets, end_row, start_offset)
          pcall(vim.api.nvim_buf_set_extmark, buf, M.namespace, buf_start, start_offset + start_col, {
            end_row = buf_end,
            end_col = end_offset + end_col,
            hl_group = "@" .. capture .. "." .. tree_language,
            priority = M.priority,
          })
          count = count + 1
        end
      end
    end
  end)

  if query_missing and count == 0 then
    return 0, "highlights query unavailable"
  end

  if count == 0 then
    return 0, "no highlight captures"
  end

  return count
end

function M.inspect_language(filetype, opts)
  opts = opts or {}
  local env = opts.env or {}
  local checks = {
    filetype = filetype,
    language = nil,
    parser = false,
    query = false,
  }

  local language_for_filetype = env.language_for_filetype or M.language_for_filetype
  local ok, language = pcall(language_for_filetype, filetype)
  if not ok or not language then
    checks.error = ok and "cannot resolve Tree-sitter language" or tostring(language)
    return checks
  end

  checks.language = language

  local sample = env.sample or "int main() { return 0; }"
  local get_string_parser = env.get_string_parser or vim.treesitter.get_string_parser
  local parser_ok, parser_or_err = pcall(get_string_parser, sample, language)
  checks.parser = parser_ok and parser_or_err ~= nil
  if not checks.parser then
    checks.error = tostring(parser_or_err)
    return checks
  end

  local query_get = env.query_get or vim.treesitter.query.get
  local query_ok, query_or_err = pcall(query_get, language, "highlights")
  checks.query = query_ok and query_or_err ~= nil
  if not checks.query then
    checks.error = query_ok and "highlights query not found" or tostring(query_or_err)
  end

  return checks
end

function M.inspect_path(path, opts)
  opts = opts or {}
  local filetype_for = opts.filetype_for_path or M.filetype_for_path
  local filetype = filetype_for(path)
  local checks = M.inspect_language(filetype, opts)
  checks.path = path
  return checks
end

local function collect_side_lines(rows, side, fallback_col_offset)
  local lines = {}
  local line_map = {}
  local col_offsets = {}

  for index, row in ipairs(rows or {}) do
    local cell = row[side]
    if cell and cell.kind ~= "blank" then
      line_map[#lines] = index - 1
      col_offsets[#lines] = cell.text_col or fallback_col_offset
      table.insert(lines, cell.text or "")
    end
  end

  return lines, line_map, col_offsets
end

function M.highlight_diff(buf, rows, side, path, col_offset, options)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return 0
  end

  vim.api.nvim_buf_clear_namespace(buf, M.namespace, 0, -1)

  local filetype = M.filetype_for_path(path)
  local language = M.language_for_filetype(filetype)
  if not language then
    log.write(options, "syntax.diff", {
      path = path,
      side = side,
      filetype = filetype or "nil",
      language = "nil",
      result = "missing-language",
    })
    return 0
  end

  local lines, line_map, col_offsets = collect_side_lines(rows, side, col_offset or 0)
  local count, reason = highlight_lines(buf, language, lines, line_map, col_offsets)
  log.write(options, "syntax.diff", {
    path = path,
    side = side,
    filetype = filetype or "nil",
    language = language,
    result = count > 0 and "ok" or reason or "no-highlights",
    count = count,
  })
  return count
end

local function fence_language(line)
  local info = line:match("^%s*```%s*(.-)%s*$")
  if not info then
    return nil
  end
  return info:match("^(%S+)")
end

local function is_closing_fence(line)
  return line:match("^%s*```%s*$") ~= nil
end

function M.highlight_markdown(buf)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return 0
  end

  vim.api.nvim_buf_clear_namespace(buf, M.namespace, 0, -1)

  local buffer_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local total = 0
  local index = 1
  while index <= #buffer_lines do
    local name = fence_language(buffer_lines[index])
    if name then
      local start_index = index
      local code_lines = {}
      local line_map = {}
      index = index + 1
      while index <= #buffer_lines and not is_closing_fence(buffer_lines[index]) do
        line_map[#code_lines] = index - 1
        table.insert(code_lines, buffer_lines[index])
        index = index + 1
      end

      local language = M.language_for_filetype(name)
      if language and #code_lines > 0 then
        total = total + highlight_lines(buf, language, code_lines, line_map, 0)
      end

      if index == start_index then
        index = index + 1
      end
    else
      index = index + 1
    end
  end

  return total
end

return M
