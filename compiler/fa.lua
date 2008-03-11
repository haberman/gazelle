--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  fa.lua

  Data structure for representing finite automata.  Both NFAs and DFAs
  can be represented using this class.

  The base class (FA/FAState) has three child classes:

  - IntFA/IntFAState represents a nonrecursive FA that transitions
    on IntSets or Epsilon.  These represent the machines that recognize
    regular expressions.

  - RTN/RTNState represents a recursive transition network: the graph
    that is built to recognize context-free grammars.  These transition
    on strings, regexes, epsilon, or on another RTN.

  - GLA/GLAState represents a lookahead automaton that represents
    LL lookahead information.

  Either child class can be deterministic or nondeterministic.  The only
  difference is whether there are epsilons / redundant transtions.

  This all needs to be refactored quite a bit, now that I have the insight
  of understanding all the different ways NFAs and DFAs are used throughout
  Gazelle.

  Copyright (c) 2007 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

require "misc"

module("fa", package.seeall)

-- This is a special edge value
Epsilon = {name="Epsilon"}
function Epsilon:new()
  -- Epsilon is a singleton
  self.singleton = self.singleton or newobject(self)
  return self.singleton
end

e = Epsilon:new()


--[[--------------------------------------------------------------------

  class State -- base class of FAState and RTNState

--------------------------------------------------------------------]]--

FAState = {name="FAState"}
function FAState:new()
  local obj = newobject(self)
  obj._transitions = {}
  return obj
end

function FAState:child_states()
  local children = Set:new()
  for edge_value, target_state in self:transitions() do
    children:add(target_state)
  end
  return children
end

function FAState:add_transition(edge_value, target_state, edge_properties)
  for e_edge_value, e_target_state, e_edge_properties in self:transitions() do
    if edge_value == e_edge_value and target_state == e_target_state
       and e_edge_properties == edge_properties then
       return
    end
  end
  table.insert(self._transitions, {edge_value, target_state, edge_properties})
end

function FAState:num_transitions()
  return #self._transitions
end

function FAState:transitions()
  local i = 0
  return function ()
    i = i + 1
    if self._transitions[i] then
      return unpack(self._transitions[i])
    else
      return nil
    end
  end
end

function FAState:transitions_for(val, prop)
  local targets = Set:new()
  for edge_val, target_state, properties in self:transitions() do
    if edge_val == val and ((prop == "ANY") or (prop == properties)) then
      targets:add(target_state)
    end
  end
  return targets
end


--[[--------------------------------------------------------------------

  class FA -- base class of IntFA and RTN

--------------------------------------------------------------------]]--

FA = {name="FA"}
function FA:new(init)
  local obj = newobject(self)
  init = init or {}

  if obj.new_state then
    obj.start = init.start or obj:new_state()
    obj.final = init.final or obj:new_state() -- for all but Thompson NFA fragments we ignore this
    if init.symbol then
      if init.properties ~= nil then
        init.properties = ShallowTable:new(init.properties)
      end

      obj.start:add_transition(init.symbol, obj.final, init.properties)
    elseif init.string then
      local int_set = IntSet:new()
      local char = init.string:sub(1, 1):byte()
      int_set:add(Range:new(char, char))
      local fa = IntFA:new{symbol=int_set}
      for i=2,#init.string do
        int_set = IntSet:new()
        char = init.string:sub(i, i):byte()
        int_set:add(Range:new(char, char))
        fa = nfa_construct.concat(fa, IntFA:new{symbol=int_set})
      end
      return fa
    end
  end

  obj.properties = {}

  return obj
end

function FA:states()
  return breadth_first_traversal(self.start, function (s) return s:child_states() end)
end

function FA:dup()
  local new_graph = self:new_graph()
  local new_states = {}

  -- duplicate states
  for state in each(self:states()) do
    new_states[state] = new_states[state] or self:new_state()
    if self.start == state then new_graph.start = new_states[state] end
    if self.final == state then new_graph.final = new_states[state] end
  end

  -- duplicate transitions
  for state in each(self:states()) do
    for edge_val, target_state, properties in state:transitions() do
      new_states[state]:add_transition(edge_val, new_states[target_state], properties)
    end
  end

  return new_graph
end

--[[--------------------------------------------------------------------

  class IntFA/IntFAState: Classes for representing machines that recognize
  regular expressions.

--------------------------------------------------------------------]]--

IntFA = FA:new()
IntFA.name = "IntFA"
function IntFA:new_graph(init)
  return IntFA:new(init)
end

function IntFA:new_state()
  return IntFAState:new()
end

function IntFA:get_outgoing_edge_values(states)
  local symbol_sets = Set:new()
  local properties_set = Set:new()
  for state in each(states) do
    for symbol_set, target_state, properties in state:transitions() do
      if properties ~= nil then
        properties_set:add(properties)
      end

      if type(symbol_set) == "table" and symbol_set.class == IntSet then
        symbol_sets:add(symbol_set)
      end
    end
  end
  symbol_sets = equivalence_classes(symbol_sets)

  -- for now, just cross symbol sets with properties.  a bit wasteful,
  -- but we'll worry about that later.
  local values = {}
  for set in each(symbol_sets) do
    for properties in each(properties_set) do
      table.insert(values, {set, properties})
    end
    table.insert(values, {set, nil})
  end

  return values
end


IntFAState = FAState:new()
IntFAState.name = "IntFAState"

function IntFAState:add_transition(edge_value, target_state, edge_properties)
  -- as a special case, IntSet edge_values can be combined if two edge_values
  -- have the same target_state and neither has any edge_properties.
  if edge_value.class == IntSet and edge_properties == nil then
    for existing_edge_value, existing_target_state, existing_edge_properties in self:transitions() do
      if existing_edge_value.class == IntSet and target_state == existing_target_state and existing_edge_properties == nil then
        existing_edge_value:add_intset(edge_value)
        return
      end
    end
  end
  FAState.add_transition(self, edge_value, target_state, edge_properties)
end

function IntFAState:transitions_for(val, prop)
  local targets = Set:new()
  if type(val) == "table" and val.class == IntSet then
    val = val:sampleint()
  end

  for edge_val, target_state, properties in self:transitions() do
    if edge_val == val or (val ~= fa.e and edge_val.class == IntSet and edge_val:contains(val)) then
      if (prop == "ANY") or (prop == properties) then
        targets:add(target_state)
      end
    end
  end
  return targets
end

--[[--------------------------------------------------------------------

  class GLA/GLAState: Classes for representing machines that represent
  lookahead information.

--------------------------------------------------------------------]]--

GLA = FA:new()
GLA.name = "GLA"
function GLA:new_graph(init)
  return GLA:new(init)
end

function GLA:new_state()
  return GLAState:new()
end

function GLA:get_outgoing_edge_values(states)
  local values = {}
  for state in each(states) do
    for edge_val, target_state, properties in state:transitions() do
      if edge_val ~= fa.e then
        table.insert(values, {edge_val, properties})
      end
    end
  end
  return values
end


GLAState = FAState:new()
GLAState.name = "GLAState"
function GLAState:new(paths)
  local obj = FAState:new()
  obj.rtn_paths = paths
end


--[[--------------------------------------------------------------------

  class RTN/RTNState: Classes for representing machines that represent
  context-free grammars.

--------------------------------------------------------------------]]--

RTN = FA:new()
RTN.name = "RTN"
function RTN:new_graph(init)
  return RTN:new(init)
end

function RTN:new_state()
  return RTNState:new()
end

function RTN:get_outgoing_edge_values(states)
  local values = {}
  for state in each(states) do
    for edge_val, target_state, properties in state:transitions() do
      if edge_val ~= fa.e then
        table.insert(values, {edge_val, properties})
      end
    end
  end
  return values
end


RTNState = FAState:new()
RTNState.name = "RTNState"

NonTerm = {name="NonTerm"}
function NonTerm:new(name)
  -- keep a cache of nonterm objects, so that we always return the same object
  -- for a given name.  This lets us compare nonterms for equality.
  if not self.cache then
    self.cache = {}
  end

  if not self.cache[name] then
    obj = newobject(self)
    obj.name = name
    self.cache[name] = obj
  end

  return self.cache[name]
end

function is_nonterm(thing)
  return (type(thing) == "table" and thing.class == NonTerm)
end

-- vim:et:sts=2:sw=2
