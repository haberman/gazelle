--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  ll.lua

  Routines for building LL lookahead tables.

  Copyright (c) 2007 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

function add_to_first_set(set, state, first_sets)
  function each_state_children(seq_state, stack)
    local children = Set:new()

    if seq_state.final then
      set:add(fa.Epsilon)
    end

    for edge_val, target_state in seq_state:transitions() do
      if fa.is_nonterm(edge_val) then
        set:add_collection(first_sets[edge_val.name])
        if first_sets[edge_val.name]:contains(fa.Epsilon) then
          children:add(target_state)
        end
      else
        set:add(edge_val)
      end
    end

    return children
  end

  local before_set_count = set:count()

  depth_first_traversal(state, each_state_children)

  if set:count() > before_set_count then
    return true
  else
    return false
  end
end

-- Comptute the FIRST sets for all nonterminals.
-- Nonterminals are allowed to derive epsilon.
function compute_first_sets(grammar)

  -- initialize all FIRST sets
  local first_sets = {}
  for nonterm, rtn in pairs(grammar) do
    first_sets[nonterm] = Set:new()

    -- if our start state is also final, add Epsilon added to the first set
    if rtn.start.final then
      first_sets[nonterm]:add(fa.Epsilon)
    end
  end

  local symbols_were_added = true
  while symbols_were_added do
    symbols_were_added = false

    for nonterm, rtn in pairs(grammar) do
      if add_to_first_set(first_sets[nonterm], rtn.start, first_sets) then
        symbols_were_added = true
      end
    end

  end

  return first_sets
end

function add_to_follow_set(set, state, first_sets, enclosing_follow_set)

  function each_state_children(seq_state, stack)
    local children = Set:new()

    -- if this state (which can directly follow this nonterminal) is final, then
    -- anything that can follow this rule (as a whole) can follow that
    -- nonterminal
    if seq_state.final then
      set:add_collection(enclosing_follow_set)
    end

    for edge_val, target_state in seq_state:transitions() do
      if fa.is_nonterm(edge_val) then
        first_set = first_sets[edge_val.name]
        set:add_collection(first_set)
        if first_set:contains(fa.Epsilon) then
          children:add(target_state)
        end
      else
        set:add(edge_val)
      end
    end

    return children
  end

  local before_set_count = set:count()
  depth_first_traversal(state, each_state_children)
  set:remove(fa.Epsilon) -- epsilon does not belong in a follow set
  if set:count() > before_set_count then
    return true
  else
    return false
  end
end

function compute_follow_sets(grammar, first_sets)
  -- initialize all FOLLOW sets to empty
  local follow_sets = {}
  for nonterm, rtn in pairs(grammar) do
    follow_sets[nonterm] = Set:new()
  end

  local symbols_were_added = true
  while symbols_were_added do
    symbols_were_added = false

    for nonterm, rtn in pairs(grammar) do  -- for every rule of the grammar
      for state in each(rtn:states()) do   -- for each state of the rule
        for edge_val, target_state in state:transitions() do  -- for each transition
          if fa.is_nonterm(edge_val) then
            if add_to_follow_set(follow_sets[edge_val.name], target_state, first_sets,
                                 follow_sets[nonterm]) then
              symbols_were_added = true
            end
          end
        end
      end
    end
  end

  return follow_sets
end

function compute_lookahead_for_nonterm(enclosing_nonterm, nonterm, state, first, follow)
  local terminals = Set:new()

  function children(seq_state)
    local children = Set:new()

    if seq_state.final then
      terminals:add_collection(follow[enclosing_nonterm])
    end

    for edge_val, target_state in seq_state:transitions() do
      if fa.is_nonterm(edge_val) then
        terminals:add_collection(first[edge_val.name])
        if first[edge_val.name]:contains(fa.Epsilon) then
          terminals:remove(fa.Epsilon)
          children:add(target_state)
        end
      else
        terminals:add(edge_val)
      end
    end

    return children
  end

  terminals:add_collection(first[nonterm])
  if terminals:contains(fa.Epsilon) then
    terminals:remove(fa.Epsilon)
    depth_first_traversal(state, children)
  end

  return terminals
end

function compute_lookahead_for_state(enclosing_nonterm, state, first, follow)
  -- find nonterminals that transition out of this state, and attempt to
  -- determine which terminal indicates each one
  local lookahead = {}
  for edge_val, target_state in state:transitions() do
    if fa.is_nonterm(edge_val) then
      local terminals = compute_lookahead_for_nonterm(enclosing_nonterm, edge_val.name,
                                                      target_state, first, follow)
      for term in each(terminals) do
        lookahead[term] = lookahead[term] or {}
        table.insert(lookahead[term], edge_val.name)
      end
    end
  end
  return lookahead
end

