
require "data_structures"

function serialize(o, maxdepth, indent, s)
  local seen = s or Stack:new()
  local t = type(o)
  local new_max_depth
  if maxdepth then new_max_depth = maxdepth-1 end
  if new_max_depth == 0 then return "<too deep>" end

  if t == "table" and seen:contains(o) then
    return "..."
  else
    seen:push(o)
  end

  if indent and type(indent) ~= "string" then
    indent = ""
  end

  local result
  local nestedIndent
  if indent then
    nestedIndent = indent .. "  "
  end

  if t == "string" then
    result = string.format("%q", o)
  elseif t == "boolean" or t == "number" or t == "function" or t == "nil" then
    result = tostring(o)
  elseif t == "table" and not (isobject(o) and has_method(o, "tostring")) then
    result = "{"
    if nestedIndent then result = result .. "\n" .. nestedIndent end
    local nextIndex = 1
    local first = true
    for k, v in pairs(o) do
      if first then
        first = false
      else
        result = result .. ", "
        if nestedIndent then result = result .. "\n" .. nestedIndent end
      end
      if type(k) == "number" and k == nextIndex then
        nextIndex = nextIndex + 1
      else
        if type(k) == "string" and string.find(k, "^[_%a][_%w]*$") then
          result = result .. k
        else
          result = result .. "[" .. serialize(k, new_max_depth, nil, seen) .. "]"
        end
        result = result .. " = "
      end
      result = result .. serialize(v, new_max_depth, nestedIndent, seen)
    end
    if indent then
      result = result .. "\n" .. indent
    end
    result = result .. "}"
  else
    result = o:tostring(nestedIndent)
  end

  seen:pop()
  return result
end

