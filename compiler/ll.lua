--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  ll.lua

  Routines for building LL lookahead tables.

  Copyright (c) 2007 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

function shallow_copy_table(t)
  local new_t = {}
  for val in each(t) do table.insert(new_t, val) end
  return new_t
end

cache = {}
function get_unique_table_for(val)
  local string_table = {}
  for entry in each(val) do table.insert(string_table, tostring(entry)) end
  local str = table.concat(string_table, "\136")
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

function table_unique_append(set, table)
  for seq in each(table) do
    local unique_seq = get_unique_table_for(seq)
    set:add(unique_seq)
  end
end

function permute(seq_set1, seq_set2)
  local permutations = {}
  for seq1 in each(seq_set1) do
    for seq2 in each(seq_set2) do
      local new_seq = {}
      for t1 in each(seq1) do table.insert(new_seq, t1) end
      for t2 in each(seq2) do table.insert(new_seq, t2) end
      table.insert(permutations, new_seq)
    end
  end
  return permutations
end

function clamp_seq_len(seqs, max_len)
  if max_len < 0 then error("Clamp seq len called with arg " .. max_len) end
  for seq in each(seqs) do
    while #seq > max_len do
      table.remove(seq)
    end
  end
  return seqs
end

function first_for_state(grammar, state, k, seen, n)
  if k == 0 then return {{}}
  elseif k < 0 then error ("first_for_state called with k " .. k)
  end

  -- for k=1,n do io.stdout:write("  ") end
  -- print(string.format("+ first_for_state(rtn=%s, k=%d)", state.rtn.name, k))
  -- n=n+1

  local first = Set:new()

  if state.final then
    table_unique_append(first, {{}})
  end

  for edge_val, dest_state in state:transitions() do
    local seen2 = Set:new(seen)
    table_unique_append(first, first_for_transition(grammar, state, edge_val, dest_state, k, seen2, n))
  end

  if first:count() == 0 then
    error("Count is 0")
  end

  -- for k=1,n do io.stdout:write("  ") end
  -- print("First for state returning: " .. serialize(first:to_array()))

  return first
end

function first_for_transition(grammar, state, edge_val, dest_state, k, seen, n)
  if k == 0 then return {{}}
  elseif k < 0 then error ("first_for_transition called with k " .. k)
  end

  seen = seen or Set:new()
  local first = Set:new()
  local one_hop_seqs = Set:new()

  -- for k=1,n do io.stdout:write("  ") end
  -- print(string.format("+ first_for_transition(rtn=%s, edge=%s, k=%d)", state.rtn.name, serialize(edge_val), k))
  -- n=n+1
  --
  if fa.is_nonterm(edge_val) then
    local nonterm_start = grammar[edge_val.name].start

    if seen:contains(nonterm_start) then
      error(string.format("Grammar is left-recursive: symbols are: [%s]", seen_str(seen)))
    end
    seen:add(nonterm_start)

    table_unique_append(one_hop_seqs, first_for_state(grammar, nonterm_start, k, seen, n))
    if nonterm_start.final then
      table_unique_append(one_hop_seqs, {{}})
    end
  else
    table_unique_append(one_hop_seqs, {{edge_val}})
  end

  -- if dest_state is final then all the sequences from one hop are
  -- also full sequences for this transition as a whole.
  if dest_state.final then
    table_unique_append(first, one_hop_seqs)
  end

  -- we now have a bunch of sequences in one_hop_seqs.  some or all of them
  -- might not be long enough (k terminals) -- if so, augment them
  -- with the paths that lead from dest_state
  local shortest_seq = math.huge
  for seq in each(one_hop_seqs) do
    shortest_seq = math.min(shortest_seq, #seq)
  end
  if shortest_seq > k then
    print("k= " .. k .. ", shortest_seq: " .. shortest_seq .. " seqs: " .. serialize(one_hop_seqs))
    for seq in each(one_hop_seqs) do
      print("This seq is: " .. serialize(seq))
    end
  end

  local trailing_seqs = first_for_state(grammar, dest_state, k - shortest_seq, nil, n)

  -- finally, cross all of the sequences we get in one hop with all the
  -- sequences we get with trailing context.  some of the resulting
  -- sequences could end up longer than k -- we cap them at k.
  -- some could also end up shorter than k, which indicates that
  -- it is possible to exit the curent nonterminal with fewer than
  -- k tokens of lookahead -- in this case we need to fall back on
  -- follow sets.
  table_unique_append(first, clamp_seq_len(permute(one_hop_seqs, trailing_seqs), k))

  -- for k=1,n do io.stdout:write("  ") end
  -- print("first_for_transition() = " .. serialize(first:to_array()))

  return first
end

function follow_for_nonterm(grammar, nonterm, k, seen, follow_nonterms, n)
  if k == 0 then return {{}}
  elseif k < 0 then error("follow_for_nonterm called with k " .. k)
  end

  --for k=1,n do io.stdout:write("  ") end
  --print(string.format("+ follow_for_nonterm(nonterm=%s, k=%d)", nonterm, k))
  --n=n+1

  local follow = Set:new()
  seen:add(nonterm)

  for state in each(follow_nonterms[nonterm]) do
    local first = first_for_state(grammar, state, k, nil, n)

    -- if any of the sequences we got from first are less than k long,
    -- we need to augment them with things that can follow this nonterm
    local short_seqs = {}
    local shortest_seq = math.huge
    for seq in each(first) do
      if #seq == k then
        table_unique_append(follow, {seq})
      else
        table.insert(short_seqs, seq)
      end
      shortest_seq = math.min(shortest_seq, #seq)
    end

    -- if this nonterm can be exited without consuming any input, then
    -- the entire follow(nonterm, k) set belongs in the follow set we
    -- are constructing.  however, we have to keep a seen set in case
    -- we are already in the middle of constructing follow(nonterm, k)
    if (state.final or shortest_seq == 0) then
      if seen:contains(state.rtn.name) then
        -- we won't recursively try to compute follow(nonterm, k)
        -- (since we're already in the middle of computing it),
        -- but as a result the follow set we're constructing right
        -- now may be incomplete, so we won't cache it.
        cache = false
      else
        local follow2 = follow_for_nonterm(grammar, state.rtn.name, k, seen, follow_nonterms, n)
        table_unique_append(follow, follow2)
      end
    end

    shortest_seq = math.max(shortest_seq, 1)

    local follow_up_seqs = follow_for_nonterm(grammar, state.rtn.name, k - shortest_seq, seen,
                                              follow_nonterms, n)
    table_unique_append(follow, clamp_seq_len(permute(short_seqs, follow_up_seqs), k))
  end

  return follow
end

function compute_lookahead(grammar, max_k)
  -- first create a list of states with more than one transition out
  local states = {}
  local ambiguous_edges = {}  -- for each state, which edges have not yet
                              -- been uniquely identified by a string of
                              -- lookahead
  local follow_nonterms = {}
  for nonterm, rtn in pairs(grammar) do
    -- make sure every nonterm gets an empty follow set if they don't follow
    -- anything
    follow_nonterms[nonterm] = follow_nonterms[nonterm] or Set:new()

    for state in each(rtn:states()) do
      state.rtn = rtn
      state.rtn.name = nonterm
      if state:num_transitions() > 0 then
        state.lookahead = {}
        table.insert(states, state)
        ambiguous_edges[state] = Set:new()
        for edge_val, target_state in state:transitions() do
          ambiguous_edges[state]:add(get_unique_table_for({edge_val, target_state}))

          -- a bit of precomputation that the follow() calculations need
          if fa.is_nonterm(edge_val) then
            follow_nonterms[edge_val.name] = follow_nonterms[edge_val.name] or Set:new()
            follow_nonterms[edge_val.name]:add(target_state)
          end
        end
      end
    end
  end
  local multiple_transition_states = shallow_copy_table(states)

  -- now compute progressively more lookahead (up to max_k) for each
  -- state in states, until no more states remain
  local k = 1
  while #states > 0  and k <= max_k do
    local still_conflicting_states = Set:new()
    for state in each(states) do
      -- set of term_seq we have discovered are still conflicting for this k
      local conflict_term_seq = Set:new()

      -- list of {edge_val, dest_state} pairs for sequences we discover to be
      -- still conflicting for this k
      local still_conflicting_edges = {}

      -- term_seq -> {edge_val, dest_state} map for sequences we currently believe
      -- to be unique for this k
      local lookaheads = {}

      for pair in each(ambiguous_edges[state]) do
        local edge_val, dest_state = unpack(pair)

        local terminals = first_for_transition(grammar, state, edge_val, dest_state, k, nil, 0)

        -- split the sequences in to sequences of less than k and sequences of k.
        -- sequences of less than k need to be augmented with follow info
        local k_seqs = Set:new()
        local short_seqs = {}
        local shortest_seq = math.huge
        for term_seq in each(terminals) do
          if #term_seq < k then
            table.insert(short_seqs, term_seq)
            if #term_seq < shortest_seq then
              shortest_seq = #term_seq
            end
          else
            table_unique_append(k_seqs, {{term_seq}})
          end
        end

        if #short_seqs > 0 then
          local follow = follow_for_nonterm(grammar, state.rtn.name, k - shortest_seq, Set:new(), follow_nonterms, 0)
          -- TODO: what if some follow seqs are too short?
          table_unique_append(k_seqs, clamp_seq_len(permute(short_seqs, follow), k))
        end

        for term_seq in each(k_seqs) do
          local unique_seq = get_unique_table_for(term_seq)
          if lookaheads[unique_seq] and lookaheads[unique_seq] ~= dest_state then
            still_conflicting_states:add(state)
            conflict_term_seq:add(unique_seq)
            table.insert(still_conflicting_edges, lookaheads[unique_seq])
            table.insert(still_conflicting_edges, pair)
            lookaheads[unique_seq] = nil
          elseif conflict_term_seq:contains(unique_seq) then
            table.insert(still_conflicting_edges, pair)
          else
            lookaheads[unique_seq] = pair
          end
        end
      end

     -- print("Inserting lookahead for nonterm " .. state.rtn.name)
      for term_seq, pair in pairs(lookaheads) do
        local edge_val, dest_state = unpack(pair)
        table.insert(state.lookahead, {term_seq, edge_val, dest_state})
        -- print("Inserting lookahead " .. serialize({term_seq, edge_val, tostring(dest_state)}))
        -- table.insert(state.lookahead, {term_seq, edge_val})
      end

      ambiguous_edges[state] = still_conflicting_edges
    end
    states = still_conflicting_states:to_array()
    k = k + 1
  end

  if #states > 0 then
    error(string.format("Grammar is not LL(%d)", max_k))
  else
    return multiple_transition_states
  end
end

