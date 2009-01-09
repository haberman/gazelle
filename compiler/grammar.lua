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
require "fa_algorithms"
require "intfa_combine"

Grammar = {name="Grammar"}

function Grammar:new()
  local obj = newobject(self)
  obj.rtns = OrderedMap:new()
  obj.terminals = {}
  obj.master_intfas = OrderedSet:new()
  obj.start = nil  -- what rule the entire grammar starts on
  return obj
end

-- Add a nonterminal and its associated RTN to the grammar.
-- TODO: how should redefinition be caught and warned/errored?
function Grammar:add_nonterm(name, rtn, slot_count, text)
  rtn.name = name
  rtn.slot_count = slot_count
  rtn.text = text
  for state in each(rtn:states()) do
    state.rtn = rtn
  end
  self.rtns:add(name, rtn)
end

-- Add a terminal and its associated IntFA to the grammar.
-- TODO: how should redefinition be caught and warned/errored?
function Grammar:add_terminal(name, intfa)
  self.terminals[name] = intfa
end

function Grammar:add_allow(what_to_allow, start_nonterm, end_nonterm)
  -- kind of a hack to do this here.
  self:determinize_rtns()

  local children_func = function(rule_name)
    if rule_name ~= end_nonterm then
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
        state:add_transition(what_to_allow, state, {name=what_to_allow.name, slotnum=-1})
      end

      return subrules
    end
  end

  depth_first_traversal(start_nonterm, children_func)
end

function Grammar:check_defined()
  for name, rtn in each(self.rtns) do
    for rtn_state in each(rtn:states()) do
      for edge_val in rtn_state:transitions() do
        if fa.is_nonterm(edge_val) and not self.rtns:contains(edge_val.name) then
          error(string.format("Rule '%s' was referred to but never defined.", edge_val.name))
        end
      end
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

function copy_attributes(rtn, new_rtn)
  new_rtn.name = rtn.name
  new_rtn.slot_count = rtn.slot_count
  new_rtn.text = rtn.text
  for state in each(new_rtn:states()) do
    state.rtn = new_rtn
  end
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
    local children = function(state, stack)
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
  strings_ordered_set = OrderedSet:new()
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
      transitions = {}
      for edge_val, target_state, properties in state:transitions() do
        table.insert(transitions, {edge_val, target_state, properties})
      end

      -- sort RTN transitions thusly:
      -- 1. terminal transitions come before nonterminal transitions
      -- 2. terminal transitions are sorted by the low integer of the range
      -- 3. nonterminal transitions are sorted by the name of the nonterminal
      -- 4. transitions with the same edge value are sorted by their order
      --    in the list of states (which is stable) (TODO: no it's not, yet)
      sort_func = function (a, b)
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

-- vim:et:sts=2:sw=2
