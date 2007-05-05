
function newobject(class)
  local obj = {}
  setmetatable(obj, class)
  obj.class = class
  class.__index = class
  return obj
end

function map(list, func)
  local newlist = {}
  for i,elem in ipairs(list) do table.insert(newlist, func(elem)) end
  return newlist
end

function inject(tab, func, val)
  for k,v in pairs(tab) do val = func(val, k, v) end
  return val
end

function new_table_with_default(func_or_value)
  if type(func_or_value) == 'function' then
    setmetatable(table, {__index = func_or_value})
  else
    setmetatable(table, {__index = function () return func_or_value end})
  end
end

-- Set
Set = {}
function Set:new(init)
  local obj = newobject(self)
  obj.elements = {}
  if type(init) == "table" then
    for i,elem in pairs(init) do
      obj:add(elem)
    end
  end
  return obj
end

function Set:contains(x)
  if self.elements[x] == nil then
    return false
  else
    return true
  end
end

function Set:add(x)
  self.elements[x] = true
end

function Set:add_array(arr)
  for i, elem in ipairs(arr) do
    self:add(elem)
  end
end

function Set:remove(x)
  self.elements[x] = false
end

function Set:to_array()
  local arr = {}
  for elem in pairs(self.elements) do
    table.insert(arr, elem)
  end
  return arr
end

function Set:each()
  return pairs(self.elements)
end

function Set:hash_key()
  local arr = {}
  for elem in pairs(self.elements) do table.insert(arr, tostring(elem)) end
  table.sort(arr)
  str = ""
  for i,elem in ipairs(arr) do str = str .. tostring(elem) end
  return str
end

function set_or_array_each(set_or_array)
  if set_or_array.class == Set then
    return set_or_array:each()
  else
    local i = 0
    return function ()
      i = i + 1
      if set_or_array[i] then return set_or_array[i] else return nil end
    end
  end
end

function breadth_first_traversal(obj, children_func)
  local seen = Set:new{obj}
  local list = {obj}
  local queue = Queue:new(obj)
  while not queue:empty() do
    local node = queue:dequeue()
    children = children_func(node) or {}
    for child_node in set_or_array_each(children) do
      if seen:contains(child_node) == false then
        seen:add(child_node)
        table.insert(list, child_node)
        queue:enqueue(child_node)
      end
    end
  end
  return list
end

