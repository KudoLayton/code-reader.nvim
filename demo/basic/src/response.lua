local response = {}

local function status_line(code)
  return "HTTP/1.1 " .. tostring(code)
end

function response.render_response(parsed)
  return {
    status = status_line(200),
    body = "Hello, " .. parsed.user .. " from " .. parsed.path,
  }
end

function response.render_error(problem)
  return {
    status = status_line(400),
    body = "Bad request: " .. problem,
  }
end

return response
