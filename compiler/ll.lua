--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  ll.lua

  Routines for building LL lookahead automata.  We use automata instead
  of tables because lookahead is almost always extremely sparse.  These
  automata are referred to as GLA (Grammar Lookahead Automata), a term
  coined by Terence Parr in his PhD thesis.

  We support calculating LL(*) with the tail recursion capability.  This
  puts us at the same capability as ANTLR, and actually is more powerful
  since ANTLR does not implement the tail recursion capability as of
  this writing.

  Copyright (c) 2008 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

require "fa"


--[[--------------------------------------------------------------------

  compute_lookahead(grammar): Calculates LL(k) lookahead and returns it
  by attaching a .gla member to every nontrivial RTN state in the grammar.

--------------------------------------------------------------------]]--

function compute_lookahead(grammar)
  local gla_needing_rtn_states = grammar:get_rtn_states_needing_gla()
  local follow_states = get_follow_states(grammar)

  for state in each(gla_needing_rtn_states) do
    state.gla = construct_gla(state, grammar, follow_states)
    state.gla.rtn_state = state
  end
end



--[[--------------------------------------------------------------------

  get_follow_states(grammar): Calculates what states can directly follow
  each nonterminal in the grammar, and returns it as a map of:
    {rtn_name -> Set of states that directly follow this RTN,
                 anywhere in the grammar}

--------------------------------------------------------------------]]--

function get_follow_states(grammar)
  local follow_states = {}

  -- initialize each set to empty.
  for name, rtn in each(grammar.rtns) do
    follow_states[rtn] = Set:new()
  end

  for name, rtn in each(grammar.rtns) do
    for state in each(rtn:states()) do
      for edge_val, dest_state in state:transitions() do
        if fa.is_nonterm(edge_val) then
          local rtn = grammar.rtns:get(edge_val.name)
          follow_states[rtn]:add(dest_state)
        end
      end
    end
  end

  -- We create a fake state for EOF.  It can follow the grammar's start symbol
  -- and it has only one transition: on EOF, it transitions to a state that
  -- itself has no transitions out of it.
  local eof_state = fa.RTNState:new()
  eof_state:add_transition(fa.eof, fa.RTNState:new())
  eof_state.rtn = {}  -- Just need a unique value.
  follow_states[eof_state.rtn] = Set:new()  -- empty, nothing ever follows it.
  follow_states[grammar.rtns:get(grammar.start)]:add(eof_state)

  return follow_states
end


--[[--------------------------------------------------------------------

  class Path: objects represent a path through various RTN states
  of the grammar.  It is used for the NFA-to-DFA construction, because
  we need to track information about the path leading up to each
  NFA state.

--------------------------------------------------------------------]]--

Path = {name="Path"}
function Path:new(rtn_state, predicted_edge, predicted_dest_state)
  local obj = newobject(self)
  obj.path = {}
  obj.current_state = rtn_state
  obj.predicted_edge = predicted_edge
  obj.predicted_dest_state = predicted_dest_state
  obj.stack = Stack:new()
  return obj
end

function Path:enter_rule(rtn, return_to_state)
  local new_path = self:dup()
  new_path.current_state = rtn.start
  table.insert(new_path.path, {"enter", rtn, return_to_state})

  -- Key point: if return_to_state is final and has no outgoing transitions,
  -- then we need not push anything on the stack.  This is the equivalent of a
  -- tail-recursive optimization, but is significant in that it allows us to
  -- calculate lookahead for languages we could not otherwise calculate
  -- lookahead for.
  if return_to_state.final and return_to_state:num_transitions() == 0 then
    -- do nothing.
  else
    new_path.stack:push(return_to_state)
  end

  return new_path
end

function Path:return_from_rule(return_to_state)
  local new_path = self:dup()
  table.insert(new_path.path, {"return", return_to_state})

  -- return_to_state must be specified iff the stack is empty.
  if new_path.stack:isempty() then
    if not return_to_state then error("Must specify return_to_state!") end
    new_path.current_state = return_to_state
  else
    if return_to_state then error("Must not specify return_to_state!") end
    new_path.current_state = new_path.stack:pop()
  end

  return new_path
end

function Path:enter_state(term, state)
  local new_path = self:dup()
  new_path.current_state = state
  table.insert(new_path.path, {"term", term, state})
  return new_path
end

function Path:signature(include_prediction)
  local sig = self.stack:to_array()
  table.insert(sig, self.current_state)
  if include_prediction then
    table.insert(sig, get_unique_table_for({self.predicted_edge, self.predicted_dest_state}))
  end
  sig = get_unique_table_for(sig)
  return sig
end

function Path:dup()
  local new_path = newobject(Path)
  new_path.path = table_shallow_copy(self.path)
  new_path.current_state = self.current_state
  new_path.predicted_edge = self.predicted_edge
  new_path.predicted_dest_state = self.predicted_dest_state
  new_path.stack = self.stack:dup()
  return new_path
end


--[[--------------------------------------------------------------------

  construct_gla(state, grammar, follow_states): Creates a GLA for the
  given state, using a special-purpose NFA-to-DFA construction.  This
  algorithm is largely based on ANTLR's LL(*) lookahead algorithm.

--------------------------------------------------------------------]]--

function construct_gla(state, grammar, follow_states)
  -- Each GLA state tracks the set of cumulative RTN paths that are
  -- represented by this state.  To bootstrap the process, we take
  -- each path to and past its first terminal.
  local gla = fa.GLA:new()
  local initial_term_transitions = {}
  local noterm_paths = Set:new()  -- paths that did not consume their first terminal

  for edge_val, dest_state in state:transitions() do
    local path = Path:new(state, edge_val, dest_state)
    if fa.is_nonterm(edge_val) then
      noterm_paths:add(path:enter_rule(grammar.rtns:get(edge_val.name), dest_state))
    else
      initial_term_transitions[edge_val] = initial_term_transitions[edge_val] or Set:new()
      initial_term_transitions[edge_val]:add(path:enter_state(edge_val, dest_state))
    end
  end

  -- For final states we also have to be able to predict when they should return.
  if state.final then
    local path = Path:new(state, 0, 0)
    for follow_state in each(follow_states[state.rtn]) do
      noterm_paths:add(path:return_from_rule(follow_state))
    end
  end

  -- Take each path to and through its first terminal transition
  for path in each(noterm_paths) do
    local paths = get_rtn_state_closure({path}, grammar, follow_states)
    for term in each(get_outgoing_term_edges(paths)) do
      for one_term_path in each(get_dest_states(paths, term)) do
        initial_term_transitions[term] = initial_term_transitions[term] or Set:new()
        initial_term_transitions[term]:add(one_term_path)
      end
    end
  end

  local queue = Queue:new()
  local gla_states = {}
  for term, paths in pairs(initial_term_transitions) do
    local new_gla_state = fa.GLAState:new(paths)
    gla.start:add_transition(term, new_gla_state)
    gla_states[paths:hash_key()] = new_gla_state
    queue:enqueue(new_gla_state)
  end

  while not queue:isempty() do
    local gla_state = queue:dequeue()
    local alt = get_unique_predicted_alternative(gla_state)
    if alt then
      -- this DFA path has uniquely predicted an alternative -- set the
      -- state final and stop exploring this path
      gla_state.final = alt
    else
      -- this path is still ambiguous about what rtn transition to take --
      -- explore it further
      local paths = get_rtn_state_closure(gla_state.rtn_paths, grammar, follow_states)
      check_for_ambiguity(gla_state)

      for edge_val in each(get_outgoing_term_edges(paths)) do
        local paths = get_dest_states(paths, edge_val)

        local maybe_new_gla_state
        if gla_states[paths:hash_key()] then
          maybe_new_gla_state = gla_states[paths:hash_key()]
        else
          maybe_new_gla_state = fa.GLAState:new(paths)
          queue:enqueue(maybe_new_gla_state)
        end
        gla_state:add_transition(edge_val, maybe_new_gla_state)
      end
    end
  end

  gla = hopcroft_minimize(gla)
  gla.longest_path = fa_longest_path(gla)

  return gla
end


--[[--------------------------------------------------------------------

  check_for_ambiguity(gla_state): If for any series of terminals
  (which is what this GLA state represents) we have more than one
  RTN path that is in the same state, *and* both have the same
  stack, we have found an ambiguity.

  Example grammars that can trigger this check:

    s -> "X" | "X";

    s -> a | b;
    a -> b;
    b -> "X";

--------------------------------------------------------------------]]--

function check_for_ambiguity(gla_state)
  local rtn_states = {}

  for path in each(gla_state.rtn_paths) do
    local signature = path:signature()
    if rtn_states[signature] then
      local err = "Ambiguous grammar for paths " .. serialize(path.path)
      error(err)
    end
    rtn_states[signature] = path
  end
end


--[[--------------------------------------------------------------------

  get_unique_predicted_alternative(gla_state): If all the RTN paths
  that arrive at this GLA state predict the same alternative, return
  it.  Otherwise return nil.

--------------------------------------------------------------------]]--

function get_unique_predicted_alternative(gla_state)
  local first_path = gla_state.rtn_paths:to_array()[1]
  local edge, state = first_path.predicted_edge, first_path.predicted_dest_state

  for path in each(gla_state.rtn_paths) do
    if path.predicted_edge ~= edge or path.predicted_dest_state ~= state then
      return nil
    end
  end

  return get_unique_table_for({edge, state})
end


--[[--------------------------------------------------------------------

  get_outgoing_term_edges(rtn_paths): Get a set of terminals that
  represent outgoing transitions from this set of RTN states.  This
  represents the set of terminals that will lead out of this GLA
  state.

--------------------------------------------------------------------]]--

function get_outgoing_term_edges(rtn_paths)
  local edges = Set:new()

  for path in each(rtn_paths) do
    for edge_val in path.current_state:transitions() do
      if not fa.is_nonterm(edge_val) then
        edges:add(edge_val)
      end
    end
  end

  return edges
end


--[[--------------------------------------------------------------------

  get_dest_states(rtn_paths, edge_val): Given the set of RTN states
  we are currently in, and a terminal transition value, return the
  list of RTN states we will be in after transitioning on this terminal.

--------------------------------------------------------------------]]--

function get_dest_states(rtn_paths, edge_val)
  local dest_states = Set:new()

  for path in each(rtn_paths) do
    for dest_state in each(path.current_state:transitions_for(edge_val, "ANY")) do
      dest_states:add(path:enter_state(edge_val, dest_state))
    end
  end

  return dest_states
end


--[[--------------------------------------------------------------------

  get_rtn_state_closure(dest_states, follow_states): Given the set of
  states we are currently in, return the list of states we could
  possibly reach without seeing a terminal (the equivalent of epsilon
  transitions).  The two epsilon transitions of this sort are
  returning from a final state and descending into a sub-rule.

--------------------------------------------------------------------]]--

function get_rtn_state_closure(rtn_paths, grammar, follow_states)
  local closure_paths = Set:new()
  local queue = Queue:new()
  local seen_follow_states = Set:new()

  for path in each(rtn_paths) do
    queue:enqueue(path)
  end

  while not queue:isempty() do
    local path = queue:dequeue()

    -- Only paths with at least one terminal transition out of them become
    -- part of the closure.
    for edge_val, dest_state in path.current_state:transitions() do
      if not fa.is_nonterm(edge_val) then
        closure_paths:add(path)
        break
      end
    end

    for edge_val, dest_state in path.current_state:transitions() do
      if fa.is_nonterm(edge_val) then
        local new_path = path:enter_rule(grammar.rtns:get(edge_val.name), dest_state)
        queue:enqueue(new_path)
      end
    end

    if path.current_state.final then
      if not path.stack:isempty() then
        -- The stack has context that determines what state we should return to.
        queue:enqueue(path:return_from_rule())
      else
        -- There is no context -- we could be in any state that follows this state
        -- anywhere in the grammar.
        for state in each(follow_states[path.current_state.rtn]) do
          if not seen_follow_states:contains(state) then
            queue:enqueue(path:return_from_rule(state))
            seen_follow_states:add(state)
          end
        end
      end
    end
  end

  return closure_paths
end

-- vim:et:sts=2:sw=2
