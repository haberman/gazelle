
function newobject(class)
  local obj = {}
  setmetatable(obj, class)
  obj.class = class
  class.__index = class
  return obj
end

-- Queue
Queue = {}
function Queue:new(init)
  local obj = newobject(self)
  obj.first = 0
  obj.last  = -1
  if init then obj:enqueue(init) end
  return obj
end

function Queue:enqueue(val)
  self.last = self.last + 1
  self[self.last] = val
end

function Queue:dequeue()
  if self:isempty() then error("Tried to dequeue an empty queue") end
  local val = self[self.first]
  self[self.first] = nil
  self.first = self.first + 1
  return val
end

function Queue:isempty()
  return self.first > self.last
end

-- Stack
Stack = {}
function Stack:new(init)
  local obj = newobject(self)
  return obj
end

function Stack:push(val)
  table.insert(self, val)
end

function Stack:pop()
  return table.remove(self)
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
  self.elements[x] = nil
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

function Set:isempty()
  local empty = true
  for elem in self:each() do
    empty = false
    break
  end
  return empty
end

function Set:hash_key()
  local arr = {}
  for elem in pairs(self.elements) do table.insert(arr, tostring(elem)) end
  table.sort(arr)
  str = ""
  for i,elem in ipairs(arr) do str = str .. tostring(elem) end
  return str
end

-- TokenStream
TokenStream = {}
function TokenStream:new(string)
  obj = newobject(self)
  obj.string = string
  return obj
end

function TokenStream:lookahead(amount)
  return obj.string:sub(amount, amount)
end

function TokenStream:get()
  char = obj.string:sub(1, 1)
  obj.string = obj.string:sub(2, -1)
  return char
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
  local queue = Queue:new(obj)
  while not queue:isempty() do
    local node = queue:dequeue()
    children = children_func(node) or {}
    for child_node in set_or_array_each(children) do
      if seen:contains(child_node) == false then
        seen:add(child_node)
        queue:enqueue(child_node)
      end
    end
  end
  return seen
end

