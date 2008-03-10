--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  ll.lua

  Routines for building LL lookahead automata.  We use automata instead
  of tables because lookahead is almost always extremely sparse.  These
  automata are referred to as GLA (Grammar Lookahead Automata), a term
  coined by Terence Parr in his PhD thesis.

  Though these GLAs are DFAs, it is not currently supported for them
  to by cyclic.  This allows us to support LL(k) for fixed k, but not
  LL(*).  Though our algorithm for building the lookahead is very
  similar to ANTLR's (which supports LL(*)), I'm not comfortable
  enough yet with my understanding of the edge cases to extend it to
  LL(*).  I want to be very sure that Gazelle can detect cases where
  it cannot succeed in building lookahead.  The bad cases I want to
  avoid are having Gazelle hanging forever, or worse, producing
  incorrect lookahead.

  Copyright (c) 2008 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--


--[[--------------------------------------------------------------------

  compute_lookahead(grammar): Calculates LL(k) lookahead and returns it
  by attaching a .gla member to every nontrivial RTN state in the grammar.

--------------------------------------------------------------------]]--

function compute_lookahead(grammar)
  local nontrivial_states = get_nontrivial_states(grammar)
  local follow_states = get_follow_states(grammar)

  for state in each(nontrivial_states) do
    state.gla = construct_gla(state, grammar, follow_states)
  end
end


--[[--------------------------------------------------------------------

  get_nontrivial_states(grammar): Returns a list of nontrivial RTN
  states.  A nontrivial state is one where you can't tell by looking
  at the state's transitions and its final status alone what
  transition you should take for a given terminal.

--------------------------------------------------------------------]]--

function get_nontrivial_states(grammar)
  local nontrivial_states = Set:new()

  for name, rtn in each(grammar.rtns) do
    for state in each(rtn:states()) do
      local is_trivial = true
      local edge_vals = Set:new()

      if state.final and state:num_transitions() > 0 then
        is_trivial = false
      else

      for edge_val in state:transitions() do
        if fa.is_nonterm(edge_val) then
          is_trivial = false
        elseif edge_vals:contains(edge_val) then
          is_trivial = false
        else
          edge_vals:add(edge_val)
        end
      end

      if is_trivial == false then
        nontrivial_states:add(state)
      end

    end
  end

  return nontrivial_states
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
    follow_states[name] = Set:new()
  end

  for name, rtn in each(grammar.rtns) do
    for state in each(rtn:states()) do
      for edge_val, dest_state in state:transitions() do
        if fa.is_nonterm(edge_val) then
          follow_states[edge_val.name]:add(dest_state)
        end
      end
    end
  end

  return follow_states
end

Path = {name="Path"}
  function Path:new(start_state, predict_edge_val, predict_dest_state)
    local obj = newobject(self)
    obj.stack = Stack:new()
    obj.current_state = start_state
    obj.seen_states = Set:new()
    obj.seen_states:add(obj.current_state)
    obj.predict_edge_val = predict_edge_val
    obj.predict_dest_state = predict_dest_state
    obj.terms = {}
    return obj
  end

  function Path:enter_rule(start, return_to)
    local new_path = self:dup()
    new_path.stack:push({return_to, new_path.seen_states:dup()})
    new_path.seen_states:add(start)
    new_path.current_state = start
    return new_path
  end

  function Path:return_from_rule()
    if self.stack:isempty() then
      obj.seen_states = Set:new()
      return nil
    else
      local new_path = self:dup()
      local state
      state, new_path.seen_states = unpack(new_path.stack:pop())
      new_path.current_state = state
      return state, new_path
    end
  end

  function Path:enter_state(term, state)
    local new_path = self:dup()
    new_path.seen_states:add(state)
    new_path.current_state = state
    table.insert(new_path.terms, term)
    return new_path
  end

  function Path:have_seen_state(state)
    return self.seen_states:contains(state)
  end

  function PathInfo:dup()
    -- TODO
  end


--[[--------------------------------------------------------------------

  construct_gla(state, grammar, follow_states): Creates a GLA for the
  given state, using a special-purpose NFA-to-DFA construction.  This
  algorithm is largely based on ANTLR's LL(*) lookahead algorithm.

--------------------------------------------------------------------]]--

function construct_gla(state, grammar, follow_states)
  -- Each GLA state tracks the set of cumulative RTN paths that are
  -- represented by this state.
  local initial_paths = {}
  for edge_val, dest_state in state:transitions() do
    local path = Path:new(state, edge_val, dest_state)
    if fa.is_nonterm(edge_val) then
      path = path:enter_rule(grammar.rtns:get(edge_val.name).start, dest_state)
    end
    table.insert(initial_paths, path)
  end

  state.gla = GLA:new(get_rtn_state_closure(initial_paths, grammar, follow_states))

  local queue = Queue:new(state.gla.start)

  while not queue:isempty() do
    local gla_state = queue:dequeue()
    check_for_ambiguity(gla_state)

    for edge_val in each(get_outgoing_term_edges(gla_state.rtn_paths)) do
      local dest_states = get_dest_states(gla_state.rtn_paths, edge_val)
      dest_states = get_rtn_state_closure(dest_states, grammar, follow_states)

      local new_gla_state = GLAState:new(dest_states)
      gla_state:add_transition(edge_val, new_gla_state)

      local alt = get_unique_predicted_alternative(new_gla_state)
      if alt then
        -- this DFA path has uniquely predicted an alternative -- set the
        -- state final and stop exploring this path
        new_gla_state.final = alt
      else
        -- this state is still ambiguous about what rtn transition to take --
        -- explore it further
        queue:enqueue(gla_state)
      end
    end
  end
end


--[[--------------------------------------------------------------------

  check_for_ambiguity(gla_state): If for any string of terminals
  (which is what this GLA state represents) we have more than one
  RTN path which has arrived at the final state for the rule we
  started from, we have found an ambiguity.

  For example, in the grammar s -> "X" | "X", we will arrive at
  a GLA state after following the terminal "X" that has two distinct
  paths that both complete s.  This is ambiguous and should error.

--------------------------------------------------------------------]]--

function check_for_ambiguity(gla_state)
  completed_paths = {}
  for path in each(gla_state.rtn_paths) do
    if path.current_state.final and path.stack:isempty() then
      table.insert(completed_paths, path)
    end
  end

  if #completed_paths > 1 then
    error("Ambiguous grammar!")
  end
end


--[[--------------------------------------------------------------------

  get_unique_predicted_alternative(gla_state): If all the RTN paths
  that arrive at this GLA state predict the same alternative, return
  it.  Otherwise return nil.

--------------------------------------------------------------------]]--

function get_unique_predicted_alternative(gla_state)
  local first_path = gla_state.rtn_paths[1]
  local edge, state = first_path.predict_edge_val, first_path.predict_dest_state

  for path in each(gla_state.rtn_paths) do
    if path.predict_edge_val ~= edge or path.predict_dest_state ~= state then
      return nil
    end
  end

  return {edge, state}
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
  local dest_states = {}

  for path in each(rtn_paths) do
    for dest_state in each(path.current_state:transitions_for(edge_val, "ANY")) do
      if path:have_seen_state(dest_state) then
        -- an RTN path has created a cycle within itself.  This is the sort
        -- of thing that could possibly be recognized with LL(*) if we
        -- supported it.  You can trigger this error with the grammar:
        --
        --  s -> "Z"* "X" | "Z"* "Y";
        error("Non-LL(k) grammar!")
      else
        table.insert(dest_states, path:enter_state(dest_state))
      end
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

function get_rtn_state_closure(rtn_paths, follow_states)
  local closure_paths = {}
  local queue = Queue:new()

  for path in each(rtn_paths) do
    queue:enqueue(path)
  end

  while not queue:isempty() do
    local path = unpack(queue:dequeue())
    table.insert(closure_paths, path)

    for edge_val, dest_state in path.current_state:transitions() do
      if fa.is_nonterm(edge_val) then
        local subrule_start = grammar.rtns.get(edge_val.name).start
        if path:have_seen_state(subrule_start) then
          error("Cyclic grammar!")
        end

        local new_path = path:enter_rule(subrule_start, dest_state)
        queue:enqueue(new_path)
      end
    end

    if path.current_state.final then
      local state, new_path = path:return_from_rule()
      if new_path:have_seen_state(state) then
        error("Cyclic grammar!")
      end
      queue:enqueue(new_path)
    end
  end

  return closure_paths
end

-- vim:et:sts=2:sw=2
