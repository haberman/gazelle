--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  fa_algorithms.lua

  Algorithms that operate on finite automata (NFAs and/or DFAs).  For
  the most part these can work on any of the FA types, since they do
  not interpret the meaning of the edges.  It is nice to keep these
  algorithms separate from the FA data structure in fa.lua.

  Copyright (c) 2008 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--


--[[--------------------------------------------------------------------

  NFA to DFA conversion.

--------------------------------------------------------------------]]--

function epsilon_closure(state)
  return depth_first_traversal(state, function(s) return s:transitions_for(fa.e, "ALL") end)
end

-- we as input an array of NFAs, one for each token we want to match simultaneously,
-- and strings describing each token.  So:
-- { {nfa1, "token string 1"},
--   {nfa2, "token string 2", etc} }
function nfas_to_dfa(nfa_string_pairs, ambiguous_ok)
  ambiguous_ok = ambiguous_ok or false
  -- First we need to mark all final states and capture groups with the token string
  local nfas = {}

  for i, nfa_string_pair in ipairs(nfa_string_pairs) do
    local nfa, token_string = unpack(nfa_string_pair)
    table.insert(nfas, nfa)

    -- Mark the nfa fragment's final state as the final state for this *token*
    nfa.final.final = token_string
  end

  -- Now combine all the nfas with alternation
  local final_nfa = nfa_construct.alt(nfas)
  return nfa_to_dfa(final_nfa, ambiguous_ok)
end

function new_dfa_state(nfa, nfa_states, ambiguous_ok)
  local dfa_state = nfa:new_state()

  -- If this is a final state for one or more of the nfas, make it an
  -- (appropriately labeled) final state for the dfa
  for nfa_state in nfa_states:each() do
    if nfa_state.final then
      if dfa_state.final and dfa_state.final ~= nfa_state.final then
        if ambiguous_ok then
          if type(dfa_state.final) ~= "table" then dfa_state.final = Set:new({dfa_state.final}) end
          dfa_state.final:add(nfa_state.final)
        else
          error("Ambiguous finality not supported yet!! (" .. tostring(dfa_state.final) .. " and " .. tostring(nfa_state.final .. ")"))
        end
      else
        dfa_state.final = nfa_state.final
      end
    end
  end

  return dfa_state
end

function nfa_to_dfa(nfa, ambiguous_ok)
  -- The sets of NFA states we need to process for outgoing transitions
  local first_nfa_states = epsilon_closure(nfa.start)
  local queue = Queue:new(first_nfa_states)

  local dfa = nfa:new_graph{start = new_dfa_state(nfa, first_nfa_states, ambiguous_ok)}
  -- The DFA states we create from sets of NFA states
  local dfa_states = {[first_nfa_states:hash_key()] = dfa.start}

  while not queue:isempty() do
    local nfa_states = queue:dequeue()
    local dfa_state = dfa_states[nfa_states:hash_key()]

    -- Generate a list of symbols that transition out of this set of NFA states.
    -- We prefer this to iterating over the entire symbol space because it's
    -- vastly more efficient in the case of a large symbol space (eg. Unicode)
    local symbol_tuples = nfa:get_outgoing_edge_values(nfa_states)

    -- For each output symbol, generate the list of destination NFA states that
    -- recognizing this symbol could put you in (including epsilon transitions).
    for symbol_tuple in each(symbol_tuples) do
      local symbol, properties = unpack(symbol_tuple)
      local dest_nfa_states = Set:new()
      for nfa_state in nfa_states:each() do
        -- equivalence classes dictate that this character represents what will
        -- happen to ALL characters in the set
        local target_states = nfa_state:transitions_for(symbol, properties)

        if target_states then
          for target_state in each(target_states) do
            dest_nfa_states:add(target_state)
            dest_nfa_states:add_collection(epsilon_closure(target_state):to_array())
          end
        end
      end

      -- this is necessary because (at the moment) get_outgoing_edge_values will generate
      -- combinations of symbol/properties that don't *actually* transtion anywhere
      -- TODO: get rid of that shortcoming
      if not dest_nfa_states:isempty() then

        -- create a DFA state for this set of NFA states, if one does not
        -- already exist.
        local dest_dfa_state = dfa_states[dest_nfa_states:hash_key()]
        if dest_dfa_state == nil then
          dest_dfa_state = new_dfa_state(nfa, dest_nfa_states, ambiguous_ok)
          dfa_states[dest_nfa_states:hash_key()] = dest_dfa_state
          queue:enqueue(dest_nfa_states)
        end

        -- create a transition from the current DFA state into the new one
        dfa_state:add_transition(symbol, dest_dfa_state, properties)
      end
    end
  end

  return dfa
end



--[[--------------------------------------------------------------------

  DFA minimization.

  hopcroft_minimize(dfa): transform a DFA into an equivalent DFA with
  the minimal number of states.  Uses Hopcroft's algorithm, which is
  O(n lg n) in the number of states, as explained by both Hopcroft and
  Gries (see BIBLIOGRAPHY for details).

--------------------------------------------------------------------]]--

function hopcroft_minimize(dfa)
  -- First create the alphabet and an inverse transition table.
  local alphabet = dfa:get_outgoing_edge_values(dfa:states())
  local inverse_transitions = {}

  for state in each(dfa:states()) do
    for symbol, dest_state, properties in state:transitions() do
      inverse_transitions[dest_state] = inverse_transitions[dest_state] or dfa:new_state()
      inverse_transitions[dest_state]:add_transition(symbol, state, properties)
    end
  end

  -- Create initial blocks, grouped by finality.
  local initial_blocks = {}
  for state in each(dfa:states()) do
    local finality = state.final or "NONE"
    initial_blocks[finality] = initial_blocks[finality] or {}
    table.insert(initial_blocks[finality], state)
  end

  local blocks = Set:new()
  local work_queue = Queue:new()
  local work_queue_set = Set:new()
  for finality, states in pairs(initial_blocks) do
    local block = Set:new(states)
    blocks:add(block)
    for state in each(states) do
      state.block = block
    end
    for symbol_tuple in each(alphabet) do
      local symbol, properties = unpack(symbol_tuple)
      work_queue:enqueue({block, symbol, properties})
      work_queue_set:add(tostring(block) .. tostring(symbol) .. tostring(properties))
    end
  end

  local num_iterations = 0
  while (not work_queue:isempty()) do
    num_iterations = num_iterations + 1
    local block, symbol, properties = unpack(work_queue:dequeue())
    work_queue_set:remove(tostring(block) .. tostring(symbol) .. tostring(properties))

    -- determine what blocks need to be split
    local states_to_split = Set:new()
    for state in each(block) do
      if inverse_transitions[state] then
        states_to_split:add_collection(inverse_transitions[state]:transitions_for(symbol, properties))
      end
    end

    -- split blocks
    local new_twins = {}
    for state_to_split in each(states_to_split) do
      for state in each(state_to_split.block) do
        local dest_state = state:transitions_for(symbol, properties):to_array()[1]
        if not (dest_state and dest_state.block == block) then
          if not new_twins[state.block] then
            local new_twin = Set:new()
            blocks:add(new_twin)
            new_twins[state.block] = new_twin
          end
          new_twins[state.block]:add(state)
        end
      end
    end

    -- fix work queue according to splits
    for old_block, new_twin in pairs(new_twins) do
      for state in each(new_twin) do
        state.block:remove(state)
        state.block = new_twin
      end

      local smaller_block
      if old_block:count() < new_twin:count() then
        smaller_block = old_block
      else
        smaller_block = new_twin
      end

      for alphabet_symbol_tuple in each(alphabet) do
        local alphabet_symbol, alphabet_properties = unpack(alphabet_symbol_tuple)
        if work_queue_set:contains(tostring(old_block) .. tostring(alphabet_symbol) .. tostring(alphabet_properties)) then
          work_queue:enqueue({new_twin, alphabet_symbol, alphabet_properties})
          work_queue_set:add(tostring(new_twin) .. tostring(alphabet_symbol) .. tostring(alphabet_properties))
        else
          work_queue:enqueue({smaller_block, alphabet_symbol, alphabet_properties})
          work_queue_set:add(tostring(smaller_block) .. tostring(alphabet_symbol) .. tostring(alphabet_properties))
        end
      end
    end
  end

  -- the blocks are the new states
  local states = {}
  for block in blocks:each() do
    states[block] = dfa:new_state()
    for state in each(block) do
      if state.final then
        states[block].final = state.final
      end
    end
  end

  local minimal_dfa = dfa:new_graph()
  minimal_dfa.start = states[dfa.start.block]
  for block in blocks:each() do
    for state in each(block) do
      for symbol, dest_state, properties in state:transitions() do
        states[block]:add_transition(symbol, states[dest_state.block], properties)
      end
    end
  end

  -- print("Num states: " .. tostring(dfa:states():count()) ..
  --       ", alphabet size: " .. tostring(#alphabet) ..
  --       ", num iterations: " .. tostring(num_iterations))
  return minimal_dfa
end


--[[--------------------------------------------------------------------

  FA comparison

  fa_isequal(fa1, fa2): Returns true if the given finite automata are
  equal, false otherwise.

--------------------------------------------------------------------]]--

function fa_isequal(fa1, fa2)
  local equivalent_states={[fa1.start]=fa2.start}
  local queue = Queue:new(fa1.start)
  local fa2_seen_states = Set:new()
  fa2_seen_states:add(fa2.start)

  while not queue:isempty() do
    local s1 = queue:dequeue()
    local s2 = equivalent_states[s1]

    if s1:num_transitions() ~= s2:num_transitions() then
      return false
    end

    if (s1.final or s2.final) then
      if not (s1.final and s2.final) then
        return false
      end

      if type(s1.final) ~= type(s2.final) then
        return false
      end

      if type(s1.final) == "table" then
        if not table_shallow_eql(s1.final, s2.final) then
          return false
        end
      elseif s1.final ~= s2.final then
        return false
      end
    end

    for edge_val, dest_state in s1:transitions() do
      local s2_dest_state = s2:dest_state_for(edge_val)
      if not s2_dest_state then
        return false
      elseif equivalent_states[dest_state] then
        if equivalent_states[dest_state] ~= s2_dest_state then
          return false
        end
      elseif fa2_seen_states:contains(s2_dest_state) then
        -- we have seen this state before, but not as equivalent to
        -- the dest_state
        return false
      else
        equivalent_states[dest_state] = s2_dest_state
        fa2_seen_states:add(s2_dest_state)
        queue:enqueue(dest_state)
      end
    end
  end

  return true
end


--[[--------------------------------------------------------------------

  FA longest path

  fa_longest_path(fa): Returns an integer representing how long the
  longest path from the start state to a final state can be.  Returns
  math.huge if the graph has cycles.

--------------------------------------------------------------------]]--

function fa_longest_path(fa)
  local longest = 0
  local current_depth = 0
  local seen = Set:new()
  function dfs_helper(state)
    seen:add(state)
    if state.final and current_depth > longest then
      longest = current_depth
    end

    for edge_val, dest_state in state:transitions() do
      if seen:contains(dest_state) then
        longest = math.huge
      else
        current_depth = current_depth + 1
        dfs_helper(dest_state)
        current_depth = current_depth - 1
      end
    end
    seen:remove(state)
  end

  dfs_helper(fa.start)

  return longest
end

