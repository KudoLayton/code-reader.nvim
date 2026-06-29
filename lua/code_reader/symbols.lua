local source = require("code_reader.source")

local M = {}

M.namespace = vim.api.nvim_create_namespace("code-reader-symbol")

local lsp_kind_groups = {
  [1] = "CodeReaderSymbolText",
  [2] = "CodeReaderSymbolRead",
  [3] = "CodeReaderSymbolWrite",
}

local extension_languages = {
  lua = "lua",
  js = "javascript",
  jsx = "javascript",
  ts = "typescript",
  tsx = "tsx",
  py = "python",
  rs = "rust",
  go = "go",
  c = "c",
  h = "c",
  cpp = "cpp",
  hpp = "cpp",
}

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function notify(message, level)
  vim.notify("Code Reader: " .. message, level or vim.log.levels.WARN)
end

local function language_for_buffer(buf, path)
  local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf })
  if filetype and filetype ~= "" then
    return filetype
  end

  local extension = path:match("%.([^.\\/]*)$")
  return extension and extension_languages[extension]
end

local function parse_query(language, query_text)
  if vim.treesitter.query and vim.treesitter.query.parse then
    return vim.treesitter.query.parse(language, query_text)
  end
  return vim.treesitter.parse_query(language, query_text)
end

local function get_range(record)
  return record.start_row, record.start_col, record.end_row, record.end_col
end

local function open_source_buffer(state, link)
  local path = source.resolve_path({ path = link.path }, { root = state.root })
  if vim.fn.filereadable(path) ~= 1 then
    notify("source file not found: " .. path)
    return nil
  end

  local previous_win = vim.api.nvim_get_current_win()
  local target_win = valid_win(state.windows and state.windows.code) and state.windows.code or previous_win
  vim.api.nvim_set_current_win(target_win)

  local ok, err = pcall(vim.cmd, "keepalt edit " .. vim.fn.fnameescape(path))
  if not ok then
    notify("cannot open source: " .. tostring(err), vim.log.levels.ERROR)
    if valid_win(previous_win) then
      vim.api.nvim_set_current_win(previous_win)
    end
    return nil
  end

  local buf = vim.api.nvim_get_current_buf()
  if valid_win(previous_win) then
    vim.api.nvim_set_current_win(previous_win)
  end

  return buf, path, target_win
end

local function collect_captures(buf, path, query_text)
  local language = language_for_buffer(buf, path)
  if not language then
    return nil, "cannot infer Tree-sitter language"
  end

  local query_ok, query_or_err = pcall(parse_query, language, query_text)
  if not query_ok then
    return nil, "invalid Tree-sitter query: " .. tostring(query_or_err)
  end

  local parser_ok, parser_or_err = pcall(vim.treesitter.get_parser, buf, language)
  if not parser_ok then
    return nil, "Tree-sitter parser is unavailable: " .. tostring(parser_or_err)
  end

  local trees = parser_or_err:parse()
  local tree = trees and trees[1]
  if not tree then
    return nil, "Tree-sitter parser returned no tree"
  end

  local captures = {}
  for id, node in query_or_err:iter_captures(tree:root(), buf, 0, -1) do
    local name = query_or_err.captures[id]
    local start_row, start_col, end_row, end_col = node:range()
    table.insert(captures, {
      name = name,
      start_row = start_row,
      start_col = start_col,
      end_row = end_row,
      end_col = end_col,
    })
  end

  if #captures == 0 then
    return nil, "Tree-sitter query matched no captures"
  end

  return captures
end

local function seed_from_captures(captures)
  for _, capture in ipairs(captures) do
    if capture.name == "code_reader.symbol" then
      return capture
    end
  end
  return captures[1]
end

local function set_extmark(buf, group, start_row, start_col, end_row, end_col)
  vim.api.nvim_buf_set_extmark(buf, M.namespace, start_row, start_col, {
    end_row = end_row,
    end_col = end_col,
    hl_group = group,
  })
end

local function lsp_clients(buf)
  local lsp = rawget(vim, "lsp")
  if not lsp then
    return {}
  end

  if lsp.get_clients then
    return lsp.get_clients({ bufnr = buf })
  end
  return lsp.get_active_clients({ bufnr = buf })
end

local function supports_document_highlight(client, buf)
  if client.supports_method then
    local ok, supported = pcall(client.supports_method, client, "textDocument/documentHighlight", { bufnr = buf })
    if ok then
      return supported
    end
  end
  return client.server_capabilities and client.server_capabilities.documentHighlightProvider
end

local function has_document_highlight_client(buf)
  for _, client in ipairs(lsp_clients(buf)) do
    if supports_document_highlight(client, buf) then
      return true
    end
  end
  return false
end

function M.clear(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, M.namespace, 0, -1)
    return
  end

  for _, listed_buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(listed_buf) then
      vim.api.nvim_buf_clear_namespace(listed_buf, M.namespace, 0, -1)
    end
  end
end

function M.apply_lsp_highlights(buf, results)
  local count = 0
  for _, response in pairs(results or {}) do
    for _, item in ipairs(response.result or {}) do
      if item.range and item.range.start and item.range["end"] then
        local group = lsp_kind_groups[item.kind] or "CodeReaderSymbolText"
        set_extmark(
          buf,
          group,
          item.range.start.line,
          item.range.start.character,
          item.range["end"].line,
          item.range["end"].character
        )
        count = count + 1
      end
    end
  end
  return count
end

local function request_lsp_highlights(buf, seed)
  local lsp = rawget(vim, "lsp")
  if not lsp then
    return 0
  end

  if not has_document_highlight_client(buf) then
    return 0
  end

  local params = {
    textDocument = lsp.util.make_text_document_params(buf),
    position = {
      line = seed.start_row,
      character = seed.start_col,
    },
  }

  local ok, results = pcall(lsp.buf_request_sync, buf, "textDocument/documentHighlight", params, 500)
  if not ok or not results then
    return 0
  end

  return M.apply_lsp_highlights(buf, results)
end

local function apply_fallback_highlights(buf, captures)
  for _, capture in ipairs(captures) do
    local start_row, start_col, end_row, end_col = get_range(capture)
    set_extmark(buf, "CodeReaderSymbolFallback", start_row, start_col, end_row, end_col)
  end
  return #captures
end

function M.highlight(state, link)
  local buf, path = open_source_buffer(state, link)
  if not buf then
    return false
  end

  M.clear(buf)

  local captures, err = collect_captures(buf, path, link.query)
  if not captures then
    notify(err)
    return false
  end

  local seed = seed_from_captures(captures)
  local start_row, start_col, end_row, end_col = get_range(seed)
  set_extmark(buf, "CodeReaderSymbolSeed", start_row, start_col, end_row, end_col)

  local lsp_count = request_lsp_highlights(buf, seed)
  if lsp_count > 0 then
    return true, "lsp", lsp_count
  end

  return true, "treesitter", apply_fallback_highlights(buf, captures)
end

return M
