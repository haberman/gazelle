
dofile("misc.lua")

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
-- class Queue


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
-- class Stack


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
-- class Set

-- Range
-- The Range is *inclusive* at both ends.
Range = {}
  function Range:new(low, high)
    if high ~= "Infinity" then assert(low <= high) end

    local obj = newobject(self)
    obj.low = low
    obj.high = high
    return obj
  end

  function Range.__lt(a, b)
    return a.low < b.low
  end

  function Range:intersects(other)
    if self.low == other.low then return true end

    if self.low > other.low then
      return (other.high == "Infinity") or (self.low <= other.high)
    else
      return (self.high == "Infinity") or (other.low <= self.high)
    end
  end

  function Range:contains(int)
    return (self.low <= int) and (self.high >= int)
  end

  function Range:tostring(display_val_func)
    if self.low == self.high then
      return display_val_func(self.low)
    else
      return display_val_func(self.low) .. "-" .. display_val_func(self.high)
    end
  end
-- class Range


-- IntSet
-- None of the ranges may overlap.
IntSet = {}
  function IntSet:new()
    local obj = newobject(self)
    obj.list = {}
    obj.negated = false
    return obj
  end

  function IntSet:add(new_range)
    for range in each(self.list) do
      if new_range:intersects(range) then
        error(string.format("Tried to add range %s that overlaps with range %s", tostring(new_range), tostring(range)))
      end
    end

    table.insert(self.list, new_range)
  end

  function IntSet:contains(int)
    for range in each(self.list) do
      if range:contains(int) then return true end
    end
    return false
  end

  function IntSet:invert()
    local new_intset = IntSet:new()
    new_intset.negated = not self.negated

    table.sort(self.list)
    local offset = 0

    for range in each(self.list) do
      if offset <= range.low-1 then
        new_intset:add(Range:new(offset, range.low-1))
      end

      if range.high == "Infinity" then
        offset = "Infinity"
      else
        offset = range.high+1
      end
    end

    if offset ~= "Infinity" then
      new_intset:add(Range:new(offset, "Infinity"))
    end

    return new_intset
  end

  function IntSet:tostring(display_val_func)
    local str = ""
    if self.negated then str = "^" end

    table.sort(self.list)
    local first = true
    for range in each(self.list) do
      if first then
        first = false
      else
        str = str .. ","
      end

      str = str .. range:tostring(display_val_func)
    end

    return str
  end
-- class IntSet

