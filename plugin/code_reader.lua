if vim.g.loaded_code_reader == 1 then
  return
end
vim.g.loaded_code_reader = 1

vim.api.nvim_create_user_command("CodeReaderOpen", function(opts)
  require("code_reader").open(opts.args)
end, {
  nargs = "?",
  complete = "file",
  desc = "Open a Code Reader explanation file",
})

vim.api.nvim_create_user_command("CodeReaderRefresh", function()
  require("code_reader").refresh()
end, {
  desc = "Reload the open Code Reader explanation",
})

vim.api.nvim_create_user_command("CodeReaderNext", function()
  require("code_reader").next()
end, {
  desc = "Move to the next Code Reader step",
})

vim.api.nvim_create_user_command("CodeReaderPrev", function()
  require("code_reader").prev()
end, {
  desc = "Move to the previous Code Reader step",
})

vim.api.nvim_create_user_command("CodeReaderGoto", function(opts)
  require("code_reader").goto_step(tonumber(opts.args))
end, {
  nargs = 1,
  desc = "Move to a Code Reader step by index",
})

vim.api.nvim_create_user_command("CodeReaderToggleFocus", function()
  require("code_reader").toggle_focus()
end, {
  desc = "Toggle Code Reader legacy focus mode",
})

vim.api.nvim_create_user_command("CodeReaderToggleDimming", function()
  require("code_reader").toggle_dimming()
end, {
  desc = "Toggle Code Reader dimming for non-focused source lines",
})

vim.api.nvim_create_user_command("CodeReaderClose", function()
  require("code_reader").close()
end, {
  desc = "Close Code Reader views",
})

vim.api.nvim_create_user_command("CodeReaderCopyRef", function(opts)
  require("code_reader").copy_ref({
    line1 = opts.line1,
    line2 = opts.line2,
    register = opts.args ~= "" and opts.args or nil,
  })
end, {
  range = true,
  nargs = "?",
  desc = "Copy a Code Reader reference for the selected range",
})
