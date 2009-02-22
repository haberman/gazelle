--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  grammar.lua

  This is the top-level data structure representing a Gazelle grammar.

  It contains all DFAs for all levels of the grammar, as well as all
  metadata about the grammar, like what the start symbol is.

  It is created and initially populated by the grammar parser.  The
  parser adds RTNs for each rule and IntFAs for each terminal, as well
  as metadata explicitly or implicitly contained in the source file.

  It is annotated with lookahead information in the form of GLAs by
  the LL lookahead calculation.

  The IntFAs for each terminal are combined into the grammar's master
  IntFAs by the IntFA-combining step.

  Finally, it is written out to bytecode by the bytecode emitting step.

  Copyright (c) 2008 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

require "data_structures"
require "misc"
require "fa_algorithms"
require "intfa_combine"

define_class("TextOffset")
  function TextOffset:initialize(line, column, offset)
    self.line = line
    self.column = column
    self.offset = offset
  end

  function TextOffset:tostring()
    return string.format("line %d, column %d", self.line, self.column)
  end
-- class TextOffset

--[[--------------------------------------------------------------------

  GrammarObj: a class for representing grammar objects (rules,
  terminals, etc) that are seen or even just referenced in a Gazelle
  grammar file.  The symbol table maps key (names) to objects of this
  type.

--------------------------------------------------------------------]]--

define_class("GrammarObj")

-- What types of grammar objects can exist in a grammar?
GrammarObj.RULE = "rule"
GrammarObj.TERMINAL = "terminal"
-- (more to come...)

  function GrammarObj:initialize(name)
    self.name = name
    self.definition = nil  -- starts out undefined
    self.explicit = false
    self.type = nil
    self.expected_types = nil
    self.explicit_offset = nil
    self.implicit_offsets = {}
  end

  function GrammarObj:set_expected(types)
    types = Set:new(types)
    if not self.expected_types then
      self.expected_types = types
    else
      local intersection = self.expected_types:intersection(types)
      if intersection:isempty() then
        if self.definition then
          error(string.format("Symbol '%s' was previously defined as %s, but its " ..
                              "use here expects it to be %s.",
                              self.name, self:type_str(), self:expected_types_str()))
        else
          error(string.format("Symbol '%s' was previously referenced as a(n) %s, but " ..
                              "its use here expects it to be %s.",
                              self.name, self:expected_types_str(),
                              self:expected_types_str(types)))
        end
      end
    end
  end

  function GrammarObj:define(definition, _type, offset, implicit)
    local explicit = not implicit
    if self.definition then
      if self.explicit == false and self.definition == definition and self.type == _type then
        -- redefinition is ok here.
      else
        error(string.format("Redefinition of symbol '%s' at %s (previous definition was at %s).",
                            self.name, offset:tostring(),
                            (self.explicit_offset or self.implicit_offsets[1]):tostring()))
      end
    elseif self.expected_types and not self.expected_types:contains(_type) then
      error(string.format("Symbol '%s' defined as %s, but previously used as if it were %s.",
            self.name, self:type_str(_type), self:expected_types_str()))
    else
      self.definition = definition
      self.type = _type
      self.expected_types = Set:new({_type})
    end
    self.explicit = self.explicit or explicit
    if explicit then
      self.explicit_offset = offset
    else
      table.insert(self.implicit_offsets, offset)
    end
  end

  function GrammarObj:type_str(_type)
    _type = _type or self.type
    return "a " .. _type
  end

  function GrammarObj:expected_types_str(types)
    types = types or self.expected_types
    types = types:to_array()
    local str = "a " .. types[1]
    if #types > 1 then
      str = str .. " or " .. types[2]
    end
    return str
  end
-- class GrammarObj

--[[--------------------------------------------------------------------

  Grammar: the Grammar class itself, which represents a single Gazelle
  grammar that is parsed from one or more input files, analzed and
  translated, and finally emitted to output.

--------------------------------------------------------------------]]--

define_class("Grammar")
function Grammar:initialize()
  -- The symbol table of objects that have been defined or referenced.
  self.objects = MemoizedObject:new(GrammarObj)

  -- The master IntFAs we build once all IntFAs are combined.
  self.master_intfas = OrderedSet:new()

  -- What rule the entire grammar starts on.
  self.start = nil

  -- @allow definitions.
  self.allow = {}

  -- Once we start processing, we assign all the rtns and terminals
  -- to separate lists for processing.
  self.rtns = nil
  self.terminals = nil
end

function Grammar:parse_source_string(string)
  local parser = RTNParser:new()
  parser:parse(CharStream:new(string), self)
end

--[[--------------------------------------------------------------------

 The next block of functions are intended for the Gazelle grammar
 parser to call as they are parsing a Gazelle grammar file.

--------------------------------------------------------------------]]--

function Grammar:get_object(name, expected)
  local obj = self.objects:get(name)
  obj:set_expected(expected)
  return obj
end

function Grammar:add_nonterm(name, rtn, slot_count, text, offset)
  rtn.name = name
  rtn.slot_count = slot_count
  rtn.text = text
  for state in each(rtn:states()) do
    state.rtn = rtn
  end
  self.objects:get(name):define(rtn, GrammarObj.RULE, offset)
end

function Grammar:add_terminal(name, string_or_intfa, text, offset)
  assert(type(name) == "string")
  assert(string_or_intfa)
  local obj = self.objects:get(name)
  obj:define(string_or_intfa, GrammarObj.TERMINAL, offset)
  return obj
end

function Grammar:add_implicit_terminal(name, string, offset)
  assert(type(name) == "string")
  local obj = self.objects:get(name)
  obj:define(string, GrammarObj.TERMINAL, offset, true)
  return obj
end

--[[--------------------------------------------------------------------

  Methods for analyzing/translating the grammar once it has been
  fully read from source files.

--------------------------------------------------------------------]]--

function Grammar:process()
  self:bind_symbols()
  -- start symbol defaults to the first rule.
  self.start = self.start or self.rtns:get_key_at_offset(1)

  -- assign priorities to RTN transitions
  --print_verbose("Assigning RTN transition priorities...")
  self:assign_priorities()

  -- make the RTNs in the grammar determistic and minimal
  --print_verbose("Convering RTN NFAs to DFAs...")
  self:determinize_rtns()
  self:process_allow()
  self:canonicalize_properties()
end

function Grammar:compute_lookahead(max_k)
  -- Generate GLAs by doing lookahead calculations.
  -- This annotates every nontrivial state in the grammar with a GLA.
  --print_verbose("Doing LL(*) lookahead calculations...")
  compute_lookahead(self, max_k)
end

-- we now have everything figured out at the RTN and GLA levels.  Now we just
-- need to figure out how many IntFAs to generate, which terminals each one
-- should handle, and generate/determinize/minimize those IntFAs.

function Grammar:bind_symbols()
  -- Ensure that all referenced symbols were defined, and replace the GrammarObj
  -- objects with the raw values.
  local objects = {}
  self.rtns = OrderedMap:new()
  self.terminals = {}
  for name, obj in self.objects:get_objects():each() do
    local definition = obj.definition
    if not definition then
      error(string.format("Symbol '%s' was referenced but never defined.", name))
    end
    assert(name == obj.name)
    objects[name] = definition
    if obj.type == GrammarObj.RULE then
      self.rtns:add(name, definition)
    else
      self.terminals[name] = definition
    end
  end

  -- Replace all references to GrammarObj objects with the actual value.
  for name, rtn in each(self.rtns) do
    for rtn_state in each(rtn:states()) do
      local new_transitions = {}
      for edge_val, dest_state, properties in rtn_state:transitions() do
        -- This is embarrassingly hacky.  Need to have a more polymorphic way
        -- of dealing with multiple kinds of edge values.
        if edge_val == fa.eof or edge_val == fa.e then
          -- do nothing
        elseif edge_val.type == GrammarObj.TERMINAL then
          edge_val = edge_val.name
        else
          edge_val = objects[edge_val.name]
        end
        table.insert(new_transitions, {edge_val, dest_state, properties})
      end
      rtn_state:clear_transitions()
      for tuple in each(new_transitions) do
        local edge_val, dest_state, properties = unpack(tuple)
        rtn_state:add_transition(edge_val, dest_state, properties)
      end
    end
  end
end


function Grammar:add_allow(what_to_allow, start_nonterm, end_nonterms)
  table.insert(self.allow, {what_to_allow, start_nonterm, end_nonterms})
end

function Grammar:process_allow()
  for allow in each(self.allow) do
    local what_to_allow, start_nonterm, end_nonterms = unpack(allow)
    local function children_func(rule_name)
      if not end_nonterms:contains(rule_name) then
        local rtn = self.rtns:get(rule_name)
        if not rtn then
          error(string.format("Error computing ignore: rule %s does not exist", rule_name))
        end

        -- get sub-rules
        local subrules = Set:new()
        for state in each(rtn:states()) do
          for edge_val, dest_state, properties in state:transitions() do
            if fa.is_nonterm(edge_val) and properties.slotnum ~= -1 then
              subrules:add(edge_val.name)
            end
          end
        end

        -- add self-transitions for every state
        for state in each(rtn:states()) do
          local allow_rtn = self.rtns:get(what_to_allow)
          state:add_transition(allow_rtn, state, {name=allow_rtn.name, slotnum=-1})
        end

        return subrules
      end
    end

    depth_first_traversal(start_nonterm, children_func)
  end
end

function Grammar:canonicalize_properties()
  for name, rtn in each(self.rtns) do
    for state in each(rtn:states()) do
      state:canonicalize_properties()
    end
  end
end

function Grammar:get_rtn_states_needing_intfa()
  local states = Set:new()
  for name, rtn in each(self.rtns) do
    for state in each(rtn:states()) do
      if state:needs_intfa() then
        states:add(state)
      end
    end
  end
  return states
end

function Grammar:get_rtn_states_needing_gla()
  local states = Set:new()
  for name, rtn in each(self.rtns) do
    for state in each(rtn:states()) do
      if state:needs_gla() then
        states:add(state)
      end
    end
  end
  return states
end

function Grammar:assign_priorities()
  -- For each non-epsilon transition in the grammar, we want to find the epsilon
  -- closure (within the rule -- no following nonterminal or final transitions)
  -- of all reverse transitions and assign any priorities the epsilon
  -- transitions have to the non-epsilon transition.

  -- Begin by building a list of reverse epsilon transitions.  For each state
  -- that has at least one epsilon transition going into it, we build a 2-tuple
  -- of {set of states that are the source of an epsilon transitions,
  --     map of priority_class -> priority in that class}
  for name, rtn in each(self.rtns) do
    local reverse_epsilon_transitions = {}
    for state in each(rtn:states()) do
      for edge_val, dest_state, properties in state:transitions() do
        if edge_val == fa.e then
          reverse_epsilon_transitions[dest_state] = reverse_epsilon_transitions[dest_state] or {Set:new(), {}}
          reverse_epsilon_transitions[dest_state][1]:add(state)
          if properties and properties.priority_class then
            if reverse_epsilon_transitions[dest_state][2][properties.priority_class] then
              error("Unexpected.")
            end
            reverse_epsilon_transitions[dest_state][2][properties.priority_class] = properties.priority
          end
        end
      end
    end

    local priorities = {}
    local function children(state, stack)
      local reverse_transitions = reverse_epsilon_transitions[state]
      if reverse_transitions then
        local child_states, priority_classes = unpack(reverse_transitions)
        for priority_class, priority in pairs(priority_classes) do
          if priorities[priority_class] then
            error("Unexpected please report the grammar that triggered this error!")
          end
          priorities[priority_class] = priority
        end
        return child_states
      end
    end
    for state in each(rtn:states()) do
      priorities = {}
      depth_first_traversal(state, children)
      priorities = get_unique_table_for_table(priorities)
      for edge_val, dest_state, properties in state:transitions() do
        if edge_val ~= fa.e then
          -- non-epsilon transitions should always have properties assigned,
          -- because they always have slotnums and slotnames.
          properties.priorities = priorities
        end
      end
      if state.final then
        state.final = {priorities = priorities}
      end
    end
  end
end

function Grammar:determinize_rtns()
  local new_rtns = OrderedMap:new()
  for name, rtn in each(self.rtns) do
    local new_rtn = nfa_to_dfa(rtn)
    copy_attributes(rtn, new_rtn)
    new_rtns:add(name, new_rtn)
  end
  self.rtns = new_rtns
end

function Grammar:minimize_rtns()
  local new_rtns = OrderedMap:new()
  for name, rtn in each(self.rtns) do
    local new_rtn = hopcroft_minimize(rtn)
    copy_attributes(rtn, new_rtn)
    new_rtns:add(name, new_rtn)
  end
  self.rtns = new_rtns
end

function Grammar:generate_intfas()
  --print_verbose("Generating lexer DFAs...")
  -- first generate the set of states that need an IntFA: some RTN
  -- states and all nonfinal GLA states.
  local states = self:get_rtn_states_needing_intfa()
  for rtn_state in each(self:get_rtn_states_needing_gla()) do
    for gla_state in each(rtn_state.gla:states()) do
      if not gla_state.final then
        states:add(gla_state)
      end
    end
  end

  -- All states in the "states" set are nonfinal and have only
  -- terminals as transitions.  Create a list of:
  --   {state, set of outgoing terms}
  -- pairs for the states.
  local state_term_pairs = {}
  for state in each(states) do
    local terms = Set:new()
    for edge_val in state:transitions() do
      if fa.is_nonterm(edge_val) or terms:contains(edge_val) then
        error(string.format("Internal error with state %s, edge %s", serialize(state, 6, "  "), serialize(edge_val)))
      end
      if edge_val ~= fa.eof then  -- EOF doesn't need to be lexed in the IntFAs
        terms:add(edge_val)
      end
    end
    assert(terms:count() > 0)
    table.insert(state_term_pairs, {state, terms})
  end

  self.master_intfas = intfa_combine(self.terminals, state_term_pairs)
end

--[[--------------------------------------------------------------------

  The remaining methods are for linearizing all the graph-like data
  structures into an ordered form, in preparation for emitting them to
  an output format like bytecode.

--------------------------------------------------------------------]]--


--[[--------------------------------------------------------------------

  Grammar:get_strings(): Returns an ordered set that contains all strings
  needed by any part of the grammar as it currently stands.

--------------------------------------------------------------------]]--

function Grammar:get_strings()
  local strings = Set:new()

  -- add the names of all the terminals
  for term, _ in pairs(self.terminals) do
    strings:add(term)
  end

  -- add the names of the rtns, and of named edges with the rtns.
  for name, rtn in each(grammar.rtns) do
    strings:add(name)

    for rtn_state in each(rtn:states()) do
      for edge_val, target_state, properties in rtn_state:transitions() do
        if properties then
          strings:add(properties.name)
        end
      end
    end
  end

  -- sort the strings for deterministic output
  strings = strings:to_array()
  table.sort(strings)
  local strings_ordered_set = OrderedSet:new()
  for string in each(strings) do
    strings_ordered_set:add(string)
  end

  return strings_ordered_set
end


--[[--------------------------------------------------------------------

  Grammar:get_flattened_rtn_list(): Creates and returns a list of all
  the RTNs, states, and transitions in a particular and stable order,
  ready for emitting to the outside world.  The RTNs themselves are
  returned in the order they were defined, except that the start RTN
  is always emitted first.

  Returns:
    OrderedMap: {rtn_name -> {
      states=OrderedSet {RTNState},
      transitions={RTNState -> {list of {edge_val, target_state, properties}}
      slot_count=slot_count
    }

--------------------------------------------------------------------]]--

function Grammar:get_flattened_rtn_list()
  local rtns = OrderedMap:new()

  -- create each RTN with a list of states
  for name, rtn in self.rtns:each() do

    -- order states such that the start state is emitted first.
    -- TODO (maybe): make this completely stable.
    local states = rtn:states()
    states:remove(rtn.start)
    states = states:to_array()
    table.insert(states, 1, rtn.start)
    states = OrderedSet:new(states)

    -- ensure that start RTN is emitted first
    if name == self.start then
      rtns:insert_front(name, {states=states, transitions={}, slot_count=rtn.slot_count})
    else
      rtns:add(name, {states=states, transitions={}, slot_count=rtn.slot_count})
    end
  end

  -- create a list of transitions for every state
  for name, rtn in each(rtns) do
    for state in each(rtn.states) do
      local transitions = {}
      for edge_val, target_state, properties in state:transitions() do
        table.insert(transitions, {edge_val, target_state, properties})
      end

      -- sort RTN transitions thusly:
      -- 1. terminal transitions come before nonterminal transitions
      -- 2. terminal transitions are sorted by the low integer of the range
      -- 3. nonterminal transitions are sorted by the name of the nonterminal
      -- 4. transitions with the same edge value are sorted by their order
      --    in the list of states (which is stable) (TODO: no it's not, yet)
      local function sort_func(a, b)
        if not fa.is_nonterm(a[1]) and fa.is_nonterm(b[1]) then
          return true
        elseif fa.is_nonterm(a[1]) and not fa.is_nonterm(b[1]) then
          return false
        elseif fa.is_nonterm(a[1]) then
          if a[1] == b[1] then
            return rtn.states:offset_of(a[2]) < rtn.states:offset_of(b[2])
          else
            return a[1].name < b[1].name
          end
        else
          if a[1].low == b[1].low then
            return rtn.states:offset_of(a[2]) < rtn.states:offset_of(b[2])
          else
            return a[1].low < b[1].low
          end
        end
      end
      table.sort(transitions, sort_func)

      rtn.transitions[state] = transitions
    end
  end

  return rtns
end

function Grammar:get_flattened_gla_list()
  local glas = OrderedSet:new()

  for name, rtn in each(self.rtns) do
    for state in each(rtn:states()) do
      if state.gla then
        glas:add(state.gla)
      end
    end
  end

  return glas
end

function copy_attributes(rtn, new_rtn)
  new_rtn.name = rtn.name
  new_rtn.slot_count = rtn.slot_count
  new_rtn.text = rtn.text
  for state in each(new_rtn:states()) do
    state.rtn = new_rtn
  end
end

-- vim:et:sts=2:sw=2
