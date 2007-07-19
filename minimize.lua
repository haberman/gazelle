--[[--------------------------------------------------------------------

  minimize.lua

  Algorithm to transform a DFA into an equivalent DFA with the
  minimal number of states.  Uses Hopcroft's algorithm, which is
  O(n lg n) in the number of states, as explained by both Hopcroft
  and Gries (see BIBLIOGRAPHY for details).

  Copyright (c) 2007 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

require "data_structures"

function hopcroft_minimize(dfa)
  -- First create the alphabet and an inverse transition table.
  local alphabet = dfa:get_outgoing_edge_values(dfa:states())
  local inverse_transitions = {}

  for state in each(dfa:states()) do
    for symbol, dest_state in state:transitions() do
      inverse_transitions[dest_state] = inverse_transitions[dest_state] or dfa:new_state()
      inverse_transitions[dest_state]:add_transition(symbol, state)
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
    for symbol in each(alphabet) do
      work_queue:enqueue({block, symbol})
      work_queue_set:add(tostring(block) .. tostring(symbol))
    end
  end

  while (not work_queue:isempty()) do
    local block, symbol = unpack(work_queue:dequeue())
    work_queue_set:remove(tostring(block) .. tostring(symbol))

    -- determine what blocks need to be split
    local states_to_split = Set:new()
    for state in each(block) do
      if inverse_transitions[state] then
        states_to_split:add_collection(inverse_transitions[state]:transitions_for(symbol))
      end
    end

    -- split blocks
    local new_twins = {}
    for state_to_split in each(states_to_split) do
      for state in each(state_to_split.block) do
        local dest_state = state:transitions_for(symbol):to_array()[1]
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
      if old_block:num_elements() < new_twin:num_elements() then
        smaller_block = old_block
      else
        smaller_block = new_twin
      end

      for alphabet_symbol in each(alphabet) do
        if work_queue_set:contains(tostring(old_block) .. tostring(alphabet_symbol)) then
          work_queue:enqueue({new_twin, alphabet_symbol})
          work_queue_set:add(tostring(new_twin) .. tostring(alphabet_symbol))
        else
          work_queue:enqueue({smaller_block, alphabet_symbol})
          work_queue_set:add(tostring(smaller_block) .. tostring(alphabet_symbol))
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
      for symbol, dest_state in state:transitions() do
        states[block]:add_transition(symbol, states[dest_state.block])
      end
    end
  end

  return minimal_dfa
end

