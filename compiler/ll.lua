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


--[[--------------------------------------------------------------------

  construct_gla(state, grammar, follow_states): Creates a GLA for the
  given state, using a special-purpose NFA-to-DFA construction.  This
  algorithm is largely based on ANTLR's LL(*) lookahead algorithm.

--------------------------------------------------------------------]]--

function construct_gla(state, grammar, follow_states)
  local gla = GLA:new(get_rtn_state_closure({[state.start]={state.rtn.name}}))

  -- Each GLA state tracks the set of cumulative RTN paths that are
  -- represented by this state.  Each RTN path is stored as a
  -- dictionary entry:
  --
  --   {RTN state -> {RTN stack, seen RTN states, predicted alt}}
  --
  -- No GLA state can have the same RTN state by two different paths;
  -- that is by defintion ambiguous.
  local queue = Queue:new(gla.start)

  while not queue:isempty() do
    local gla_state = queue:dequeue()
    for edge_val in each(get_outgoing_term_edges(gla_state.rtn_states)) do
      local dest_states = get_dest_states(gla_state.rtn_states, edge_val)
      dest_states = get_rtn_state_closure(dest_states)
      local new_gla_state = GLAState:new(dest_states)
      gla_state:add_transition(edge_val, new_gla_state)

      if new_gla_state:unique_predicted_alternative() then
        -- this DFA path has uniquely predicted an alternative -- set the
        -- state final and stop exploring this path
        new_gla_state.final = new_gla_state:unique_predicted_alternative()
      else
        -- this state is still ambiguous about what rtn transition to take --
        -- explore it further
        queue:enqueue(gla_state)
      end
    end
  end
end


--[[--------------------------------------------------------------------

  get_outgoing_term_edges(rtn_states): Get a set of terminals that
  represent outgoing transitions from this set of RTN states.  This
  represents the set of terminals that will lead out of this GLA
  state.

--------------------------------------------------------------------]]--

function get_outgoing_term_edges(rtn_states)
  local edges = Set:new()

  for state, _ in pairs(rtn_states) do
    for edge_val in state:transitions() do
      if not fa.is_nonterm(edge_val) then
        edges:add(edge_val)
      end
    end
  end

  return edges
end


--[[--------------------------------------------------------------------

  get_dest_states(rtn_states, edge_val): Given the set of RTN states
  we are currently in, and a terminal transition value, return the
  list of RTN states we will be in after transitioning on this terminal.

--------------------------------------------------------------------]]--

function get_dest_states(rtn_states, edge_val)
  local dest_states = {}

  for state, state_info in pairs(rtn_states) do
    for dest_state in each(state:transitions_for(edge_val, "ANY")) do
      local new_state_info = {state_info[1], state_info[2], Set:new(state_info[3])}
      if dest_states[dest_state] then
        -- Two different RTN paths have converged on the same state
        -- for the same input.  You can trigger this error with the grammar:
        --   s -> a | b;
        --   a -> b;
        --   b -> "X";
        error("Ambiguous grammar!")
      elseif new_state_info[3]:contains(dest_state) then
        -- an RTN path has created a cycle within itself.  This is the sort
        -- of thing that could possibly be recognized with LL(*) if we
        -- supported it.  You can trigger this error with the grammar:
        --
        --  s -> "Z"* "X" | "Z"* "Y";
        error("Non-LL(k) grammar!")
      else
        new_state_info[3]:add(dest_state)
        dest_states[dest_state] = new_state_info
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

function get_rtn_state_closure(rtn_states, follow_states)
  local closure_states = {}
  local queue = Queue:new()

  for state, triple in pairs(rtn_states) do
    queue:enqueue({state, triple})
  end

  while not queue:isempty() do
    local state, triple = unpack(queue:dequeue())
    local stack, seen_states, predicted_alt = unpack(triple)
    if closure_states[state] then
      -- Two paths converge on the same state, when evaluating epislon
      -- transitions.  The easiest way to trigger this is with
      -- left-recursion:
      --   s -> (s "X")?
      --
      -- I haven't convinced myself for sure whether there are
      -- other ways to trigger this.
      error("grammar error, probably left-recursion")
    end
    closure_states[state] = triple

    if state.final then
      if #stack > 0 then
        local popped_stack = stack:dup()
      else
        for upstate in each(follow_states[popped_stack:pop]) do
          -- what are corner cases here with seen_states?
          queue:enqueue({upstate, {popped_stack, , predicted_alt}})
        end

      end
    end

  end
end

  --   {RTN state -> {RTN stack, seen RTN states, predicted alt}}

function get_rtn_state_closure_dfs(closure, closure_search_stack,
                                   state, stack, seen_states, alt)
  if closure_search_stack:contains(state) then
    -- We have encountered a loop within an epsilon-only path.
    -- This can occur in a few different situations:
    --   - left-recursion like: s -> (s "X")?;
    --   - ambiguous constructs like: s -> a*; a -> "X"?;
    --
    -- TODO: return the path of states that loops, for better
    -- error reporting.
    error("loop within an epsilon-only path!")
  elseif seen_states:contains(state) then
    -- An epsilon path causes us to re-enter a state that we were
    -- already in earlier on this path.
  if closure[state] then
  end
end

-- vim:et:sts=2:sw=2
