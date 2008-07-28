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

  Copyright (c) 2007-2008 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

require "misc"

module("fa", package.seeall)

-- Class for representing special-case edge values that have only one
-- instance for the whole program.
SingletonEdgeValue = {name="SingletonEdgeValue"}
function SingletonEdgeValue:new(name)
  self.singletons = self.singletons or {}
  -- we index each singleton by name, creating new ones lazily.
  self.singletons[name] = self.singletons[name] or newobject(self)
  return self.singletons[name]
end

-- This is a special edge value that represents a transition that can be
-- taken without consuming any input.
e = SingletonEdgeValue:new("Epsilon")

-- This is a special edge value that represents a GLA transition that can
-- be taken when EOF is seen.
eof = SingletonEdgeValue:new("EOF")


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

function FAState:dest_state_for(val)
  local states = self:transitions_for(val, "ANY")
  if states:count() > 1 then
    error(">1 transition found")
  elseif states:count() == 0 then
    return nil
  else
    local dest
    for dest_state in each(states) do
      dest = dest_state
    end
    return dest
  end
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

function IntFA:to_dot()
  str = ""
  states = self:states():to_array()
  --table.sort(states, function (a, b) return a.statenum < b.statenum end)
  for i,state in ipairs(states) do
    local label = ""
    local peripheries = 1
    if state == self.start then label = "Begin" end
    if state == self.final or state.final then
      if label ~= "" then
        label = label .. "NEWLINE" .. state.final
      else
        label = state.final
      end
      peripheries = 2
    end
    label = label:gsub("[\"\\]", "\\%1")
    label = label:gsub("NEWLINE", "\\n")
    str = str .. string.format('  "%s" [label="%s", peripheries=%d];\n', tostring(state), label, peripheries)
    for char, tostate, attributes in state:transitions() do
      local print_char
      if char == fa.e then
        print_char = "ep"
      -- elseif char == "(" then
      --   print_char = "start capture"
      -- elseif char == ")" then
      --   print_char = "end capture"
      elseif type(char) == "string" then
        print_char = char
      elseif type(char) == 'table' and char.class == IntSet then
        if char:isunbounded() then char = char:invert() end
        print_char = char:toasciistring()
      else
        print(serialize(char, 3, true))
        print_char = string.char(char)
      end
      print_char = print_char:gsub("[\"\\]", "\\%1")
      print_char = print_char:gsub("NEWLINE", "\\n")
      str = str .. string.format('  "%s" -> "%s" [label="%s"];\n', tostring(state), tostring(tostate), print_char)
    end
  end
  return str
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

function GLA:to_dot(indent, suffix)
  local str = ""
  suffix = suffix or ""
  indent = indent or ""
  for state in each(self:states()) do
    peripheries = 1
    extra_label = ""
    if state.final then
      peripheries = 2
      if state.final[1] == 0 then   -- the special value that means "return"
        extra_label = "Return"
      else
        for edge_val, dest_state, properties in self.rtn_state:transitions() do
          if edge_val == state.final[1] and dest_state == state.final[2] then
            extra_label = tostring(properties.slotnum)
          end
        end
      end
    end
    if self.start == state then extra_label = "Start" end
    str = str .. string.format('%s"%s" [label="%s" peripheries=%d]\n',
                                indent, tostring(state) .. suffix, escape(extra_label), peripheries)
    for edge_val, target_state in state:transitions() do
      if edge_val == fa.eof then
        edge_val = "EOF"
      end
      str = str .. string.format('%s"%s" -> "%s" [label="%s"]\n',
                    indent, tostring(state) .. suffix, tostring(target_state) .. suffix,
                    escape(edge_val))
    end
  end
  return str
end


GLAState = FAState:new()
GLAState.name = "GLAState"
function GLAState:new(paths)
  local obj = FAState:new()
  obj.rtn_paths = paths
  return obj
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

function escape(str)
  return str:gsub("[\"\\]", "\\%1")
end

function RTN:to_dot(indent, suffix, intfas, glas)
  suffix = suffix or ""
  str = indent .. "rankdir=LR;\n"
  -- str = str .. indent .. string.format('label="%s"\n', self.name)
  for state in each(self:states()) do
    peripheries = 1
    extra_label = ""
    color = ""
    if state.gla then
      if state.gla.longest_path == 1 then
        color = " fillcolor=\"cornflowerblue\""
      elseif state.gla.longest_path == 2 then
        color = " fillcolor=\"gold\""
      elseif state.gla.longest_path > 2 then
        color = " fillcolor=\"firebrick\""
      end
      color = color .. " style=\"filled\""
    end
    if state.final then peripheries = 2 end
    if self.start == state then extra_label = "Start" end
    if intfas and state.intfa then
      if extra_label ~= "" then
        extra_label = extra_label .. "\\n"
      end
      extra_label = extra_label .. "I: " .. tostring(intfas:offset_of(state.intfa))
    end
    if glas and state.gla then
      if extra_label ~= "" then
        extra_label = extra_label .. "\\n"
      end
      extra_label = extra_label .. "G: " .. tostring(glas:offset_of(state.gla))
    end
    str = str .. string.format('%s"%s" [label="%s" peripheries=%d%s]\n',
                                indent, tostring(state) .. suffix, extra_label,
                                peripheries, color)
    for edge_val, target_state in state:transitions() do
      if fa.is_nonterm(edge_val) then
        str = str .. string.format('%s"%s" -> "%s" [label="<%s>"]\n',
                      indent, tostring(state) .. suffix, tostring(target_state) .. suffix,
                      escape(edge_val.name))
      else
        --if attributes.regex_text[edge_val] then
        --  edge_val = "/" .. attributes.regex_text[edge_val] .. "/"
        --end
        if edge_val == fa.eof then
          edge_val = "EOF"
        end
        str = str .. string.format('%s"%s" -> "%s" [label="%s"]\n',
                      indent, tostring(state) .. suffix, tostring(target_state) .. suffix,
                      escape(edge_val))
      end
    end
  end
  return str
end


RTNState = FAState:new()
RTNState.name = "RTNState"

-- A trivial state is one where you can tell just by looking
-- at the state's transitions and its final status alone what
-- transition you should take for a given terminal.
function RTNState:needs_gla()
  if self.final then
    -- a final state needs a GLA if it has any outgoing transitions
    if self:num_transitions() > 0 then
      return true
    else
      return false
    end
  else
    -- a nonfinal state needs a GLA if it has more than one
    -- outgoing transition and either:
    --  - at least one of those transitions is a nonterminal
    --  - there are two or more terminal transitions for the same state
    -- TODO: what about states with exactly 1 outgoing nonterminal
    -- transition?  We don't technically need a GLA's help to
    -- figure out the right transition.
    if self:num_transitions() == 1 then
      return false
    else
      local edge_vals = Set:new()
      for edge_val in self:transitions() do
        if fa.is_nonterm(edge_val) then
          return true
        else
          if edge_vals:contains(edge_val) then
            return true
          end
          edge_vals:add(edge_val)
        end
      end
      return false
    end
  end
end

-- In most cases, a state needs an intfa if it doesn't have a GLA,
-- but there are a few exceptions.  Final states with no transitions
-- don't need an intfa.  Neither do states that have only one
-- nonterminal transition.
function RTNState:needs_intfa()
  if self:needs_gla() then
    return false
  else
    if self.final then
      return false
    elseif self:num_transitions() == 1 and fa.is_nonterm(self._transitions[1][1]) then
      return false
    else
      return true
    end
  end
end


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
