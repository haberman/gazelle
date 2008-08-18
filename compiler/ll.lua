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

  compute_lookahead(grammar): Calculates LL(*) lookahead and returns it
  by attaching a .gla member to every nontrivial RTN state in the grammar.

--------------------------------------------------------------------]]--

function compute_lookahead(grammar, k)
  local gla_needing_rtn_states = grammar:get_rtn_states_needing_gla()
  local follow_states = get_follow_states(grammar)

  for state in each(gla_needing_rtn_states) do
    state.gla = construct_gla(state, grammar, follow_states, k)
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
  eof_state.rtn = {name="eof"}  -- Just need a unique value.
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
  obj.history = {}
  obj.lookahead_k = 0
  obj.prediction = {predicted_edge, predicted_dest_state}
  obj.stack = Stack:new()

  obj.original_state = rtn_state
  obj.current_state = rtn_state
  obj.presumed_stack = {}
  obj.seen_sigs = Set:new()
  obj.is_cyclic = false
  obj.is_epsilon_cyclic = false
  obj.epsilon_seen_sigs = Set:new()
  obj.epsilon_seen_follow_states = Set:new()
  obj.left_recursive_seen_states = Set:new()
  return obj
end

function Path:enter_rule(rtn, return_to_state)
  local new_path = self:dup()
  new_path.current_state = rtn.start
  table.insert(new_path.history, {"enter", rtn.name})
  if new_path.left_recursive_seen_states:contains(rtn.name) then
    new_path.is_left_recursive = true
  end
  new_path.left_recursive_seen_states:add(rtn.name)

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

  new_path:check_for_cycles()
  return new_path
end

function Path:return_from_rule(return_to_state)
  local new_path = self:dup()
  if return_to_state then
    new_path.epsilon_seen_follow_states:add(return_to_state)
    table.insert(new_path.presumed_stack, return_to_state)
    table.insert(new_path.history, {"return", return_to_state.rtn.name})
  else
    table.insert(new_path.history, {"return"})
  end

  -- return_to_state must be specified iff the stack is empty.
  if new_path.stack:isempty() then
    if not return_to_state then error("Must specify return_to_state!") end
    new_path.current_state = return_to_state
  else
    if return_to_state then error("Must not specify return_to_state!") end
    new_path.current_state = new_path.stack:pop()
  end

  new_path:check_for_cycles()
  return new_path
end

function Path:enter_state(term, state)
  local new_path = self:dup()
  new_path.current_state = state
  new_path.lookahead_k = new_path.lookahead_k + 1
  table.insert(new_path.history, {"term", term})

  -- Clear everything concerned with epsilon transitions.
  new_path.epsilon_seen_sigs = Set:new()
  new_path.epsilon_seen_follow_states = Set:new()
  new_path.left_recursive_seen_states = Set:new()

  new_path:check_for_cycles()
  return new_path
end

function Path:signature(include_prediction)
  local sig = self.stack:to_array()
  table.insert(sig, self.current_state)
  if include_prediction then
    table.insert(sig, self.prediction)
  end
  sig = get_unique_table_for(sig)
  return sig
end

function Path:check_for_cycles()
  if self.seen_sigs:contains(self:signature()) then
    self.is_cyclic = true
  end
  if self.epsilon_seen_sigs:contains(self:signature()) then
    self.is_epsilon_cyclic = true
  end
  self.seen_sigs:add(self:signature())
  self.epsilon_seen_sigs:add(self:signature())
end

function Path:check_for_epsilon_cycles()
  if self.seen_sigs:contains(self:signature()) then
    self.is_cyclic = true
  end
  self.seen_sigs:add(self:signature())
end

function Path:is_regular()
  local seen_states = Set:new()
  for return_to_state in each(self.stack) do
    if seen_states:contains(return_to_state) then
      return false
    end
    seen_states:add(return_to_state)
  end
  return true
end

function Path:dup()
  local new_path = newobject(Path)
  new_path.history = table_shallow_copy(self.history)
  new_path.lookahead_k = self.lookahead_k
  new_path.prediction = self.prediction
  new_path.stack = self.stack:dup()

  new_path.original_state = self.original_state
  new_path.current_state = self.current_state
  new_path.presumed_stack = table_shallow_copy(self.presumed_stack)
  new_path.seen_sigs = self.seen_sigs:dup()
  new_path.is_cyclic = self.is_cyclic
  new_path.is_epsilon_cyclic = self.is_epsilon_cyclic
  new_path.epsilon_seen_sigs = self.epsilon_seen_sigs:dup()
  new_path.epsilon_seen_follow_states = self.epsilon_seen_follow_states:dup()
  new_path.left_recursive_seen_states = self.left_recursive_seen_states:dup()

  return new_path
end


--[[--------------------------------------------------------------------

  construct_gla(state, grammar, follow_states): Creates a GLA for the
  given state, using a special-purpose NFA-to-DFA construction.  This
  algorithm is largely based on ANTLR's LL(*) lookahead algorithm.

--------------------------------------------------------------------]]--

function construct_gla(state, grammar, follow_states, k)
  -- Each GLA state tracks the set of cumulative RTN paths that are
  -- represented by this state.  To bootstrap the process, we take
  -- each path to and past its first terminal.
  local gla = fa.GLA:new()
  local initial_term_transitions = {}
  local noterm_paths = Set:new()  -- paths that did not consume their first terminal
  local prediction_languages = {}

  for edge_val, dest_state in state:transitions() do
    local path = Path:new(state, edge_val, dest_state)
    -- Initialize all prediction languages to "fixed" (which is what they are
    -- until demonstrated otherwise).
    prediction_languages[path.prediction] = "fixed"
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

    if k then
      if gla_state.lookahead_k > k then
        error("Grammar is not LL(k) for user-specified k=" .. k)
      end
    else
      check_for_termination_heuristic(gla_state, prediction_languages)
    end

    check_for_ambiguity(gla_state)

    local alt = get_unique_predicted_alternative(gla_state.rtn_paths)
    if alt then
      -- this DFA path has uniquely predicted an alternative -- set the
      -- state final and stop exploring this path
      gla_state.final = alt
    else
      -- this path is still ambiguous about what rtn transition to take --
      -- explore it further
      local paths = get_rtn_state_closure(gla_state.rtn_paths, grammar, follow_states)

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
  local signatures = {}

  for path in each(gla_state.rtn_paths) do
    local signature = path:signature()
    signatures[signature] = signatures[signature] or Set:new()
    signatures[signature]:add(path)
  end

  for signature, paths in pairs(signatures) do
    if not get_unique_predicted_alternative(paths) then
      -- We know at this point that we cannot support this grammar.
      -- However we do a little bit more detective work to understand
      -- why this is, as best as we can, to give a good message to the user.

      local common_k = math.huge
      local presumed_stacks = {}
      for path in each(paths) do
        local stack = get_unique_table_for(path.presumed_stack)
        presumed_stacks[stack] = presumed_stacks[stack] or Set:new()
        presumed_stacks[stack]:add(path)

        common_k = math.min(common_k, #path.presumed_stack)
      end

      for _, same_stack_paths in pairs(presumed_stacks) do
        if same_stack_paths:count() > 1 then
          err = "Ambiguous grammar for paths: "
          for path in each(same_stack_paths) do
            err = err .. serialize(path.history) .. " AND "
          end
          error(err)
        end
      end

      local common_stacks = {}
      for path in each(paths) do
        local stack = get_unique_table_for(clamp_table(path.presumed_stack, common_k))
        if common_stacks[stack] then
          error("Gazelle cannot handle this grammar.  It is not Strong-LL or full-LL")
        end
        common_stacks[stack] = true
      end

      -- TODO: find a grammar that exercises this case.
      error("This grammar is full-LL but not strong-LL")
    end
  end
end


--[[--------------------------------------------------------------------

  check_for_termination_heuristic(gla_state, prediction_languages): Check
  to see if the grammar fails a heuristic that detects most non-LL(*)
  grammars.  It will have some false positives (deciding that a grammar
  is not LL(*) when in fact it is), but I am convinced that most real-world
  grammars will not fall into this case.  For false positives, the user
  can always opt to specify an explicit 'k' value for LL(k), which will
  prevent Gazelle from using this heuristic and always extend the search
  at least 'k' terminals.

  The heursitic is based on the fact that we *know* we can generate
  correct lookahead if the grammar falls into one of two cases:

  - all alternatives have regular lookahead languages.  In this case
    we build a GLA which is guaranteed to be regular because it is the
    combination of a bunch of regular languages.
  - at most one alternative has a nonregular lookahead language.  In
    this case all of the other alternatives must have LL(k) (LL(*)
    won't do) lookahead languages.  This works because once we have
    determined k for the other alternatives, we can enumerate all
    strings of terminals <= length k in the nonregular language,
    and combine them with the other LL(k) lookahead.

  So to detect if we are dealing with a language we can't parse, we
  need to do the following check:

  if any of the alternatives have nonregular lookahead
    if any of the *other* alternatives are cyclic or nonregular
      return failure

--------------------------------------------------------------------]]--

function check_for_termination_heuristic(gla_state, prediction_languages)
  for path in each(gla_state.rtn_paths) do
    if not path:is_regular() then
      prediction_languages[path.prediction] = "nonregular"
    end

    if path.is_cyclic and prediction_languages[path.prediction] ~= "nonregular" then
      prediction_languages[path.prediction] = "cyclic"
    end
  end

  for prediction, language in pairs(prediction_languages) do
    if language == "nonregular" then
      for prediction2, language2 in pairs(prediction_languages) do
        if prediction ~= prediction2 and language2 ~= "fixed" then
          -- TODO: more info about which languages they were.
          error("Language is probably not LL(k) or LL(*): when calculating lookahead for a state in " .. gla_state.rtn_paths:to_array()[1].prediction[2].rtn.name .. ", one lookahead language was nonregular, others were not all fixed")
        end
      end
    end
  end
end


--[[--------------------------------------------------------------------

  get_unique_predicted_alternative(gla_state): If all the RTN paths
  that arrive at this GLA state predict the same alternative, return
  it.  Otherwise return nil.

--------------------------------------------------------------------]]--

function get_unique_predicted_alternative(rtn_paths)
  local first_prediction = rtn_paths:to_array()[1].prediction

  for path in each(rtn_paths) do
    if path.prediction ~= first_prediction then
      return nil
    end
  end

  return first_prediction
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

-- This method is a helper method for the depth-first search of
-- get_rtn_state_closure.
function get_rtn_state_closure_for_path(path, grammar, follow_states)
  function child_epsilon_paths(path)
    local child_paths = {}
    for edge_val, dest_state in path.current_state:transitions() do
      if fa.is_nonterm(edge_val) then
        local dest_rtn = grammar.rtns:get(edge_val.name)
        local new_path = path:enter_rule(dest_rtn, dest_state)
        if new_path.is_left_recursive then
          -- TODO: mention what rules were left-recursive
          error("Grammar is not LL(*): it is left-recursive!")
        elseif new_path.is_epsilon_cyclic then
          error("Ambiguous grammar -- it has cycles in its epsilon transitions!")
        end
        table.insert(child_paths, new_path)
      end
    end

    if path.current_state.final then
      if not path.stack:isempty() then
        -- The stack has context that determines what state we should return to.
        table.insert(child_paths, path:return_from_rule())
      else
        -- There is no context -- we could be in any state that follows this state
        -- anywhere in the grammar.
        local follow_base
        if #path.presumed_stack > 0 then
          follow_base = path.presumed_stack[#path.presumed_stack]
        else
          follow_base = path.original_state
        end
        for state in each(follow_states[follow_base.rtn]) do
          if not path.epsilon_seen_follow_states:contains(state) then
            table.insert(child_paths, path:return_from_rule(state))
          end
        end
      end
    end
    return child_paths
  end

  return depth_first_traversal(path, child_epsilon_paths)
end

function get_rtn_state_closure(paths, grammar, follow_states)
  local closure = Set:new()
  for path in each(paths) do
    closure:add_collection(get_rtn_state_closure_for_path(path, grammar, follow_states))
  end
  return closure
end

-- vim:et:sts=2:sw=2
