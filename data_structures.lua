
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
    if init then
      obj:add_collection(init)
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

  function Set:add_collection(arr)
    for elem in each(arr) do
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

  function Set:num_elements()
    local num = 0
    for elem in pairs(self.elements) do
      num = num + 1
    end
    return num
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
    assert(low <= high)

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
      return self.low <= other.high
    else
      return other.low <= self.high
    end
  end

  function Range.intersection(a, b)
    local low  = math.max(a.low, b.low)
    local high = math.min(a.high, b.high)
    if low > high then
      return nil
    else
      return Range:new(low, high)
    end
  end

  function Range.overlapping_or_adjacent(a, b)
    return math.max(a.low, b.low) <= (math.min(a.high, b.high)+1)
  end

  function Range.union(a, b)
    if Range.overlapping_or_adjacent(a, b) then
      return {Range:new(math.min(a.low, b.low), math.max(a.high, b.high))}
    else
      if a.high < b.high then
        return {a, b}
      else
        return {b, a}
      end
    end
  end

  function Range:is_superset(other)
    return (self.low <= other.low) and (self.high >= other.high)
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
    local intersecting = {}
    local nonintersecting = {}
    for range in each(self.list) do
      if new_range:overlapping_or_adjacent(range) then
        table.insert(intersecting, range)
      else
        table.insert(nonintersecting, range)
      end
    end

    local superrange = new_range
    for range in each(intersecting) do
      superrange = superrange:union(range)[1]
    end

    self.list = nonintersecting
    table.insert(self.list, superrange)
  end

  function IntSet:add_intset(intset)
    for range in each(intset.list) do
      self:add(range)
    end
  end

  function IntSet:contains(int)
    for range in each(self.list) do
      if range:contains(int) then return true end
    end
    return false
  end

  function IntSet:intersects(range)
    for my_range in each(self.list) do
      if my_range:intersects(range) then return true end
    end
    return false
  end

  function IntSet:sampleint()
    if self.negated then
      error("sampleint for non-negated sets only, please")
    end

    if #self.list == 0 then
      return nil
    else
      return self.list[1].low
    end
  end

  function IntSet:is_superset(other)
    for range in each(other.list) do
      local superset = false
      for my_range in each(self.list) do
        if my_range:is_superset(range) then
          superset = true
          break
        end
      end
      if superset == false then return false end
    end

    return true
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
      offset = range.high+1
    end

    if offset ~= math.huge then
      new_intset:add(Range:new(offset, math.huge))
    end

    return new_intset
  end

  function IntSet:tostring(display_val_func)
    local obj = self

    for range in each(obj.list) do
      if range.high == math.huge then
        obj = obj:invert()
        break
      end
    end

    local str = ""
    if obj.negated then str = "^" end

    table.sort(obj.list)
    local first = true
    for range in each(obj.list) do
      if first then
        first = false
      else
        str = str .. ","
      end

      str = str .. range:tostring(display_val_func)
    end

    return str
  end

  function IntSet:toasciistring()
    local convert_func = function (x)
      if x == math.huge then
        return "del"
      elseif x < 33 then
        return string.format("\\%3o", x)
      else
        return string.char(x)
      end
    end
    return self:tostring(convert_func)
  end

  function IntSet:tointstring()
    return self:tostring(function (x) return tostring(x) end)
  end
-- class IntSet

