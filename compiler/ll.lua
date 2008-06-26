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

  TODO: add support for GLAs that instruct a final RTN state to return.

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

  class Path: objects represent a path through various RTN states
  of the grammar.  It is used for the NFA-to-DFA construction, because
  we need to track information about the path leading up to each
  NFA state.

--------------------------------------------------------------------]]--

Path = {name="Path"}
  function Path:new(start_state, predict_edge_val, predict_dest_state)
    local obj = newobject(self)
    obj.stack = Stack:new()

    obj.current_seq_num = 0
    obj.next_seq_num = 1
    obj.states = {{start_state, obj.current_seq_num}}
    obj.all_stack = {{{start_state.rtn, obj.current_seq_num}}}

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

    new_path.stack:push({return_to, new_path.seen_states:dup(),
                         new_path.current_seq_num})
    new_path.current_seq_num = new_path.next_seq_num
    new_path.next_seq_num = new_path.next_seq_num + 1
    local st_off = 1 + new_path.stack:count()
    new_path.all_stack[st_off] = new_path.all_stack[st_off] or {}
    table.insert(new_path.all_stack[st_off], {start.rtn, new_path.current_seq_num})

    table.insert(new_path.states, {start, new_path.current_seq_num})
    new_path.seen_states:add(start)
    new_path.current_state = start

    return new_path
  end

  function Path:return_from_rule()
    if self.stack:isempty() then
      self.seen_states = Set:new()
      return nil
    else
      local new_path = self:dup()
      local state
      state, new_path.seen_states, new_path.current_seq_num = unpack(new_path.stack:pop())
      new_path.current_state = state
      table.insert(new_path.states, {state, new_path.current_seq_num})
      return state, new_path
    end
  end

  function Path:enter_state(term, state)
    local new_path = self:dup()
    new_path.seen_states:add(state)
    new_path.current_state = state
    table.insert(new_path.states, {state, new_path.current_seq_num})
    table.insert(new_path.terms, term)
    return new_path
  end

  function Path:have_seen_state(state)
    return self.seen_states:contains(state)
  end

  function Path:dup()
    local new_path = newobject(Path)
    new_path.stack = self.stack:dup()
    new_path.current_seq_num = self.current_seq_num
    new_path.next_seq_num = self.next_seq_num
    new_path.states = table_shallow_copy(self.states)
    new_path.all_stack = table_copy(self.all_stack, 2)
    new_path.seen_states = self.seen_states:dup()
    new_path.terms = table_shallow_copy(self.terms)
    new_path.current_state = self.current_state
    new_path.predict_edge_val = self.predict_edge_val
    new_path.predict_dest_state = self.predict_dest_state
    return new_path
  end

  function Path:to_dot()
    local str = "digraph untitled{\n"
    for i, st_entry in ipairs(self.all_stack) do
      str = str .. string.format("  subgraph cluster%d {\n", i)
      str = str .. "    rankdir=LR;\n"
      for rtn_seq_pair in each(st_entry) do
        local rtn, seq_num = unpack(rtn_seq_pair)
        str = str .. string.format("    subgraph clusterrtn%d {\n", seq_num)
        str = str .. rtn:to_dot("      ", tostring(seq_num))
        str = str .. "    }\n"
      end
      str = str .. "  }\n"
    end

    for i=1,(#self.states-1) do
      local st1, seq1 = unpack(self.states[i])
      local st2, seq2 = unpack(self.states[i+1])
      str = str .. string.format('  "%s%d" -> "%s%d" [style=bold]\n',
                                 tostring(st1), seq1, tostring(st2), seq2)
    end
    str = str .. "}"

    return str
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
  local gla = fa.GLA:new{start=start_gla_state}
  local initial_term_transitions = {}

  for edge_val, dest_state in state:transitions() do
    local path = Path:new(state, edge_val, dest_state)
    if fa.is_nonterm(edge_val) then
      -- we need to expand all paths until they reach a terminal transition.
      path = path:enter_rule(grammar.rtns:get(edge_val.name).start, dest_state)
      local paths = get_rtn_state_closure({path}, grammar, follow_states)
      for term in each(get_outgoing_term_edges(paths)) do
        for one_term_path in each(get_dest_states(paths, term)) do
          initial_term_transitions[term] = initial_term_transitions[term] or {}
          table.insert(initial_term_transitions[term], one_term_path)
        end
      end
    else
      initial_term_transitions[edge_val] = initial_term_transitions[edge_val] or {}
      table.insert(initial_term_transitions[edge_val], path:enter_state(edge_val, dest_state))
    end
  end

  local queue = Queue:new()
  for term, paths in pairs(initial_term_transitions) do
    local new_gla_state = fa.GLAState:new(paths)
    gla.start:add_transition(term, new_gla_state)
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

        local new_gla_state = fa.GLAState:new(paths)
        gla_state:add_transition(edge_val, new_gla_state)
        queue:enqueue(new_gla_state)
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
    local err = "Ambiguous grammar for terms " .. serialize(completed_paths[1].terms) ..
                ", paths follow:\n"
    for path in each(completed_paths) do
      err  = err .. path:to_dot()
    end
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
      --print(string.format("Not unique: %s/%s vs %s/%s", serialize(path.predict_edge_val), tostring(path.predict_dest_state), serialize(edge), tostring(state)))
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

    -- add once we decide how to represent EOF
    --
    -- local state = path.current_state
    -- if path.stack:isempty() and state.final and state.rtn == grammar.start then
    --   edges:add(EOF)
    -- end
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
      table.insert(dest_states, path:enter_state(edge_val, dest_state))
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
  local closure_paths = {}
  local queue = Queue:new()

  for path in each(rtn_paths) do
    queue:enqueue(path)
  end

  while not queue:isempty() do
    local path = queue:dequeue()
    table.insert(closure_paths, path)

    for edge_val, dest_state in path.current_state:transitions() do
      if fa.is_nonterm(edge_val) then
        local subrule_start = grammar.rtns:get(edge_val.name).start
        local new_path = path:enter_rule(subrule_start, dest_state)
        queue:enqueue(new_path)
      end
    end

    if path.current_state.final then
      local state, new_path = path:return_from_rule()
      if state then
        -- There was a stack entry indicating a state to return to.
        queue:enqueue(new_path)
      else
        for state in each(follow_states[path.current_state.rtn.name]) do
          -- TODO
          -- queue:enqueue(path:return_from_rule_into_state(state))
        end
      end
    end
  end

  return closure_paths
end

-- vim:et:sts=2:sw=2
