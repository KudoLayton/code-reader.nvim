local request = require("src.request")
local response = require("src.response")

local app = {}

local function build_context(raw_request)
  return {
    raw_request = raw_request,
    received_at = "demo-clock",
  }
end

function app.handle(raw_request)
  local context = build_context(raw_request)
  local parsed = request.parse_request(context.raw_request)
  local ok, problem = request.validate_request(parsed)

  if not ok then
    return response.render_error(problem)
  end

  return response.render_response(parsed)
end

return app
