local M = {}

local function normalize(path)
  return (path or ""):gsub("\\", "/")
end

local function resolve(state, path)
  if not (state and state.root and path) then
    return nil
  end
  return vim.fn.fnamemodify(state.root .. "/" .. normalize(path), ":p")
end

function M.resolve_path(state, evidence)
  return resolve(state, evidence and evidence.path)
end

function M.resolve_editable_path(state, evidence)
  return resolve(state, evidence and evidence.editable_path)
end

function M.clear(state)
  local image = state and state.sketch_image
  if image and image.clear then
    pcall(image.clear, image)
  end
  if state then
    state.sketch_image = nil
  end
end

function M.render(state, evidence)
  M.clear(state)
  local ok, image_api = pcall(require, "image")
  if not ok or not image_api or not image_api.from_file then
    return false, "image.nvim is not available"
  end
  local path = M.resolve_path(state, evidence)
  if not path or vim.fn.filereadable(path) ~= 1 then
    return false, "sketch SVG cannot be read"
  end
  local created, image, image_err = pcall(image_api.from_file, path, {
    id = "code-reader-sketch-" .. tostring(state.current) .. "-" .. tostring(evidence.id),
    window = state.windows.code,
    buffer = state.buffers.sketch,
  })
  if not created or not image then
    return false, tostring(image_err or "image.nvim could not create an image")
  end
  local rendered, render_err = pcall(image.render, image)
  if not rendered then
    return false, tostring(render_err)
  end
  state.sketch_image = image
  return true
end

function M.inspect()
  local ok, image_api = pcall(require, "image")
  if not ok or not image_api then
    return false, "image.nvim is not available"
  end
  return true, "image.nvim is available"
end

return M
