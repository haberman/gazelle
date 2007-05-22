
function map(list, func)
  local newlist = {}
  for i,elem in ipairs(list) do table.insert(newlist, func(elem)) end
  return newlist
end

function inject(tab, func, val)
  for k,v in pairs(tab) do val = func(val, k, v) end
  return val
end

