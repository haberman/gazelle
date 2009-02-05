--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  misc.lua

  Miscellaneous algorithms that don't belong anywhere else.

  Copyright (c) 2007-2008 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

function newobject(class)
  local obj = {}
  setmetatable(obj, class)
  obj.class = class
  class.__index = class
  return obj
end

-- each(foo): returns an iterator; if the object supports the each method,
--            call that, otherwise return an iterator for a plain array.
function each(array_or_eachable_obj)
  if array_or_eachable_obj.class then
    return array_or_eachable_obj:each()
  else
    local array = array_or_eachable_obj
    local i = 0
    return function ()
      i = i + 1
      if array[i] then return array[i] else return nil end
    end
  end
end

function table_shallow_eql(tbl1, tbl2)
  for k,v in pairs(tbl1) do
    if tbl1[k] ~= tbl2[k] then return false end
  end
  for k,v in pairs(tbl2) do
    if tbl1[k] ~= tbl2[k] then return false end
  end
  return true
end

function table_copy(t, max_depth)
  local new_t = {}
  for k, v in pairs(t) do
    if max_depth > 1 and type(v) == "table" then
      v = table_copy(v, max_depth - 1)
    end
    new_t[k] = v
  end
  return new_t
end

function table_shallow_copy(t)
  return table_copy(t, 1)
end

function get_common_prefix_len(arrays)
  local common_len = 0
  while common_len <= #arrays[1] do
    local elem = arrays[1][common_len+1]
    for array in each(arrays) do
      if array[common_len+1] ~= elem then
        return common_len
      end
    end
    common_len = common_len + 1
  end
  return common_len
end

cache = {}
function get_unique_table_for(val)
  local string_table = {}
  for entry in each(val) do table.insert(string_table, tostring(entry)) end
  local str = table.concat(string_table, "\136")
  if not cache[str] then
    cache[str] = table_shallow_copy(val)
  end
  return cache[str]
end

function get_unique_table_for_table(val)
  local string_table = {}
  local keys = {}
  for k,v in pairs(val) do
    table.insert(keys, k)
  end

  table.sort(keys)
  for k in each(keys) do
    table.insert(string_table, tostring(k))
    table.insert(string_table, tostring(val[k]))
   end
  local str = table.concat(string_table, "\136")
  if not cache[str] then
    cache[str] = table_shallow_copy(val)
  end
  return cache[str]
end

function depth_first_traversal(obj, children_func)
  local seen = Set:new{obj}
  local stack = Stack:new()
  stack:push(obj)
  depth_first_traversal_helper(obj, children_func, stack, seen)
  return seen
end

function depth_first_traversal_helper(obj, children_func, stack, seen)
  local children = children_func(obj, stack) or {}
  for child in each(children) do
    if not seen:contains(child) then
      seen:add(child)
      stack:push(child)
      depth_first_traversal_helper(child, children_func, stack, seen)
      stack:pop()
    end
  end
end

-- all ints within each IntSet are assumed to be equivalent.
-- Given this, return a new list of IntSets, where each IntSet
-- returned is considered equivalent across ALL IntSets.
function equivalence_classes(int_sets)
  local BEGIN = 0
  local END = 1

  local events = {}
  for int_set in each(int_sets) do
    if int_set.negated then int_set = int_set:invert() end
    for range in each(int_set.list) do
      table.insert(events, {range.low, BEGIN, int_set})
      table.insert(events, {range.high+1, END, int_set})
    end
  end

  local cmp_events = function(a, b)
    if a[1] == b[1] then
      return b[2] < a[2]   -- END events should go before BEGIN events
    else
      return a[1] < b[1]
    end
  end

  table.sort(events, cmp_events)

  local nested_regions = Set:new()
  local last_offset = nil
  classes = {}
  for event in each(events) do
    local offset, event_type, int_set = unpack(event)

    if last_offset and last_offset < offset and (not nested_regions:isempty()) then
      local hk = nested_regions:hash_key()
      classes[hk] = classes[hk] or IntSet:new()
      classes[hk]:add(Range:new(last_offset, offset-1))
    end

    if event_type == BEGIN then
      nested_regions:add(int_set)
    else
      nested_regions:remove(int_set)
    end
    last_offset = offset
  end

  local ret = {}
  for hk, int_set in pairs(classes) do
    table.insert(ret, int_set)
  end
  return ret
end

function str_join(list, separator)
  local str = ""
  for i, string in ipairs(list) do
    str = str .. string
    if i < #list then
      str = str .. separator
    end
  end
  return str
end

function table_contains(table, element)
  for i, table_element in pairs(table) do
    if element == table_element then
      return true
    end
  end
  return false
end

function clamp_table(tab, len)
  local my_table = table_shallow_copy(tab)
  while #my_table > len do
    table.remove(my_table)
  end
  return my_table
end

-- vim:et:sts=2:sw=2
