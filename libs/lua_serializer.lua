local lua_serializer = {}

local function needs_bracket(key)
  return not key:match('^[%a_][%a%d_]*$')
end

local function escape_string(s)
  s = s:gsub('\\', '\\\\')
  s = s:gsub("'",  "\\'")
  s = s:gsub('\n', '\\n')
  s = s:gsub('\r', '\\r')
  return "'" .. s .. "'"
end

local function sorted_keys(t)
  local str_keys, num_keys = {}, {}
  for k in pairs(t) do
    if type(k) == 'number' then
      num_keys[#num_keys + 1] = k
    else
      str_keys[#str_keys + 1] = k
    end
  end
  table.sort(str_keys)
  table.sort(num_keys)
  local result = {}
  for _, k in ipairs(num_keys) do result[#result + 1] = k end
  for _, k in ipairs(str_keys) do result[#result + 1] = k end
  return result
end

local function serialize_value(v, depth)
  local t = type(v)
  if t == 'string' then
    return escape_string(v)
  elseif t == 'number' or t == 'boolean' then
    return tostring(v)
  elseif t == 'table' then
    local keys = sorted_keys(v)
    if #keys == 0 then return '{}' end
    local indent = string.rep('  ', depth)
    local inner  = string.rep('  ', depth + 1)
    local parts  = {'{\n'}
    for _, k in ipairs(keys) do
      local val = v[k]
      if val ~= nil then
        local key_str
        if type(k) == 'string' and not needs_bracket(k) then
          key_str = k
        elseif type(k) == 'string' then
          key_str = '[' .. escape_string(k) .. ']'
        else
          key_str = '[' .. tostring(k) .. ']'
        end
        parts[#parts + 1] = inner .. key_str .. ' = ' .. serialize_value(val, depth + 1) .. ',\n'
      end
    end
    parts[#parts + 1] = indent .. '}'
    return table.concat(parts)
  end
  return 'nil'
end

function lua_serializer.to_lua(t)
  return 'return ' .. serialize_value(t, 0) .. '\n'
end

return lua_serializer
