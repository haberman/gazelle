--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  misc.lua

  Miscellaneous algorithms that don't belong anywhere else.

  Copyright (c) 2007-2008 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

class_mt = {
  __newindex = function(obj, key, value)
    if type(value) == "function" then
      obj.methods[key] = value
    else
      rawset(obj, key, value)
    end
  end,
  -- For doing explicit superclass method calls.
  __index = function(obj, key)
    return obj.methods[key]
  end
}

function isobject(maybe_obj)
  local mt = getmetatable(maybe_obj)
  return type(maybe_obj) == "table" and mt and mt.__class
end

function has_method(obj, method)
  return getmetatable(obj).__class.methods[method] ~= nil
end

function assign_and_record(class)
  local members = class.members
  return function(obj, key, value)
    members[key] = true
    return rawset(obj, key, value)
  end
end

function assign_if_member(members)
  return function(obj, key, value)
    local member = members[key]
    if member then
      return rawset(obj, key, value)
    else
      error(string.format("Attempted to assign property '%s' to an object of class '%s', " ..
                          "but that property was not defined in its initialize() method.",
                           key, getmetatable(obj).__class.name))
    end
    return rawset(obj, key, value)
  end
end

function find_or_error(class)
  local methods = class.methods
  local members = class.members
  return function(obj, key)
    local method = methods[key]
    if method then
      return method
    end
    local ismember = members[key]
    if ismember then
      return nil
    else
      error(string.format("Attempted to access non-existent method or member " ..
                          "'%s' on an object of class '%s'.", key, class.name))
    end
  end
end

function define_class(name, superclass)
  local class={name=name, methods={}, members={}}
  if name ~= "Object" then
    superclass = superclass or Object
    setmetatable(class.methods, {__index=superclass.methods})
  end
  class.superclass = superclass
  local obj_metatable={__class=class, __index=find_or_error(class)}
  local members_initialized = false
  function class:new(...)
    local obj = class:new_empty()
    -- This is the first object of the class we have created.
    -- We rely on its constructor to define its members.
    obj_metatable.__newindex = assign_and_record(class)
    obj:initialize(...)
    obj_metatable.__newindex = assign_if_member(class.members)
    function class:new(...)
      local obj = class:new_empty()
      obj:initialize(...)
      return obj
    end
    return obj
  end
  function class:new_empty()
    local obj = {}
    obj.class = class
    setmetatable(obj, obj_metatable)
    return obj
  end
  -- Do this here so that :new above is a class method, but all others become
  -- object methods.
  setmetatable(class, class_mt)
  rawset(_G, name, class)
end

define_class("Object")

define_class("MemoizedObject")
  function MemoizedObject:initialize(class)
    self.memoized_class = class
    self.objects = OrderedMap:new()
  end

  function MemoizedObject:get(name)
    return self.objects:get_or_insert_new(
        name, function() return self.memoized_class:new(name) end)
  end

  function MemoizedObject:get_objects()
    return self.objects
  end
-- class MemoizedObject

--[[--------------------------------------------------------------------

  strict.lua, from the Lua distribution.  Forces all globals to be
  assigned at global scope before they are referenced.  This prevents:
  - assigning to a global inside a function, if you have not previously
    assigned to the global at global scope.
  - referencing a global before it has been defined.

--------------------------------------------------------------------]]--

local getinfo, error, rawset, rawget = debug.getinfo, error, rawset, rawget

local mt = getmetatable(_G)
if mt == nil then
  mt = {}
  setmetatable(_G, mt)
end

mt.__declared = {}

local function what ()
  local d = getinfo(3, "S")
  return d and d.what or "C"
end

mt.__newindex = function (t, n, v)
  if not mt.__declared[n] then
    local w = what()
    if w ~= "main" and w ~= "C" then
      error("assign to undeclared variable '"..n.."'", 2)
    end
    mt.__declared[n] = true
  end
  rawset(t, n, v)
end
  
mt.__index = function (t, n)
  if not mt.__declared[n] and what() ~= "C" then
    error("variable '"..n.."' is not declared", 2)
  end
  return rawget(t, n)
end


-- each(foo): returns an iterator; if the object supports the each method,
--            call that, otherwise return an iterator for a plain array.
function each(array_or_eachable_obj)
  assert(type(array_or_eachable_obj) == "table")
  if array_or_eachable_obj.each then
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

  local function cmp_events(a, b)
    if a[1] == b[1] then
      return b[2] < a[2]   -- END events should go before BEGIN events
    else
      return a[1] < b[1]
    end
  end

  table.sort(events, cmp_events)

  local nested_regions = Set:new()
  local last_offset = nil
  local classes = {}
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
