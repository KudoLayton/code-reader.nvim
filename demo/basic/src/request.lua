local request = {}

function request.parse_request(raw_request)
  local method = raw_request.method or "GET"
  local path = raw_request.path or "/"
  local user = raw_request.user or "anonymous"

  return {
    method = method,
    path = path,
    user = user,
  }
end

function request.validate_request(parsed)
  if parsed.method ~= "GET" and parsed.method ~= "POST" then
    return false, "unsupported method"
  end

  if parsed.path == "" then
    return false, "missing path"
  end

  return true, nil
end

return request
