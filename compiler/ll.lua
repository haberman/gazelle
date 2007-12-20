--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  ll.lua

  Routines for building LL lookahead tables.

  Copyright (c) 2007 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

function shallow_copy_table(t)
  local new_t = {}
  for k, v in pairs(t) do
    new_t[k] = v
  end
  return new_t
end

cache = {}
function get_unique_table_for(val)
  local str = ""
  local keys = {}
  for key in pairs(val) do table.insert(keys, key) end
  table.sort(keys)
  for key in each(keys) do
    if type(val[key]) == "table" and val[key].class == fa.Epsilon then
      str = str .. "|" .. key .. ":e"
    else
      str = str .. "|" .. key .. ":s-" .. tostring(val[key])
    end
  end

  if not cache[str] then
    cache[str] = shallow_copy_table(val)
  end
  return cache[str]
end

function seen_str(seen)
  local nonterms = {}
  for state in each(seen) do
    table.insert(nonterms, state.rtn.name)
  end
  return table.concat(nonterms, ", ")
end

function dfs_helper(grammar, state, stack, seen, terminals, k, lookahead)
  if #terminals >= k or terminals[#terminals] == fa.Epsilon then
    table.insert(lookahead, terminals)
  else
    if seen:contains(state) then
      error(string.format("Grammar is left-recursive: symbols are [%s]", seen_str(seen)))
    end
    seen:add(state)

    -- if state.lookahead_cache then
    --   for cached_terminals, cached_stack, cached_state in state.lookahead_cache do
    --     local new_stack = shallow_copy_table(stack)
    --     local new_terminals = shallow_copy_table(terminals)
    --     for term in each(cached_terminals) do
    --       table.insert(new_terminals, term)
    --     end
    --     for st_item in each(cached_stack) do
    --       table.insert(new_stack, st_item)
    --     end
    --     dfs_helper(grammar, cached_state, new_stack, Set:new(), new_terminals, k, lookahead)
    --   end
    -- else
      for edge_val, dest_state in state:transitions() do
        if fa.is_nonterm(edge_val) then
          local new_stack = shallow_copy_table(stack)
          local new_seen  = Set:new(seen)
          table.insert(new_stack, {edge_val.name, dest_state})
          print("    Recursing into " .. edge_val.name .. ", seen is " .. seen_str(seen))
          dfs_helper(grammar, grammar[edge_val.name].start, new_stack, new_seen, terminals,
                     k, lookahead)
          print("    Done recursing")
        else
          local new_terminals = shallow_copy_table(terminals)
          table.insert(new_terminals, edge_val)
          dfs_helper(grammar, dest_state, stack, Set:new(), new_terminals, k, lookahead)
        end
      end

      if state.final then
        if #stack == 0 then
          local new_terminals = shallow_copy_table(terminals)
          table.insert(new_terminals, fa.Epsilon)
          dfs_helper(grammar, nil, stack, nil, new_terminals, k, lookahead)
        else
          new_stack = shallow_copy_table(stack)
          edge_val, dest_state = unpack(table.remove(new_stack))
          dfs_helper(grammar, dest_state, new_stack, seen, terminals, k, lookahead)
        end
      end
    --end
  end
end

function compute_lookahead_for_transition(grammar, state, edge_val, dest_state, k)
  -- do a depth-first search looking for terminals that can be reached
  -- by following this transition
  local rtn_stack = {}
  local seen_states = Set:new()
  local terminals = {}
  local lookahead = {}
  local first_state

  if fa.is_nonterm(edge_val) then
    table.insert(rtn_stack, {edge_val.name, dest_state})
    first_state = grammar[edge_val.name].start
  else
    table.insert(terminals, edge_val)
    first_state = dest_state
  end

  dfs_helper(grammar, first_state, rtn_stack, seen_states, terminals, k, lookahead)

  return lookahead
end

function compute_lookahead(grammar, max_k)
  -- first create a list of states with more than one transition out
  local states = {}
  for nonterm, rtn in pairs(grammar) do
    for state in each(rtn:states()) do
      state.rtn = rtn
      if state:num_transitions() > 0 then
        table.insert(states, state)
      end
    end
  end

  -- now compute progressively more lookahead (up to max_k) for each
  -- state in states, until no more states remain
  local k = 1
  while #states > 0  and k <= max_k do
    print(string.format("Processing k=%d, remaining nonterms=", k, seen_str(states)))
    local still_conflicting_states = Set:new()
    for state in each(states) do
      state.lookahead = {}
      print(string.format("++ Processing state in %s", state.rtn.name))
      local lookaheads = {}
      for edge_val, dest_state, properties in state:transitions() do
        print(string.format("  ++ Processing edge %s, properties=%s", serialize(edge_val), serialize(properties)))
        local terminals = compute_lookahead_for_transition(grammar, state, edge_val, dest_state, k)
        for term_seq in each(terminals) do
          local unique_seq = get_unique_table_for(term_seq)
          if lookaheads[unique_seq] and unique_seq[-1] ~= fa.Epsilon then
            if lookaheads[unique_seq] ~= dest_state and unique_seq[-1] ~= fa.Epsilon then
              still_conflicting_states:add(state)
            end
          else
            lookaheads[unique_seq] = dest_state
            -- table.insert(state.lookahead, {unique_seq, edge_val, dest_state})
            table.insert(state.lookahead, {unique_seq, edge_val})
          end
        end
      end
      print("  " .. serialize(state.lookahead))
      if still_conflicting_states:contains(state) then
        print("(still conflicting)")
      else
        print("(no longer conflicting!)")
      end
    end
    states = still_conflicting_states:to_array()
    k = k + 1
  end

  if #states > 0 then
    error(string.format("Grammar is not LL(%d)", max_k))
  else
    return true
  end
end

