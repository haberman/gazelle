
Partition = {}
function Partition:new(states)
  obj = newobject(self)

  obj.states = states
  obj.inverse_transitions = new_table_with_default(function () return {} end)
  obj.inbound_chars       = new_table_with_default(0)

  for state in states():each() do
    for char, to_state in pairs(state.transitions) do
      obj.inverse_transitions[to_state][char] = state
      obj.inbound_chars[char] = obj.inbound_chars[char] + 1
    end
  end
end

function Partition:split(states_to_remove)
  obj = newobject(self.class)

  obj.states = states_to_remove
  obj.inverse_transitions = self.inverse_transitions
  obj.inbound_chars       = new_table_with_default(0)

  for state in set_or_array_each(states_to_remove) do
    for char in pairs(state.transitions) do
      obj.inbound_chars[char] = obj.inbound_chars[char] + 1
      self.inbound_chars[char] = self.inbound_chars[chars] - 1
      if self.inbound_chars[char] == 0 then self.inbound_chars[char] = nil end
    end
  end

  return obj
end

function minimize_dfa(dfa)
  local partition1 = Partition:new(dfa:states())
  local blocks = {partition1, partition1:split(dfa:final_states())}
  if blocks[1].states:count() > blocks[2].states:count() then
    blocks[1], blocks[2] = blocks[2], blocks[1]
  end

  local work_list = {}
  local alphabet = Set:new()
  for char in pairs(blocks[1].inbound_chars) do
    work_list[#work_list + 1] = {blocks[1], char}
    alphabet:add(char)
  end
  for char in pairs(blocks[2].inbound_chars) do
    if alphabet:contains(char) == false then
      work_list[#work_list + 1] = {blocks[2], char}
    end
  end

  while #work_list > 0 do
    block, letter = unpack(
  end
end

function minimize_dfa(dfa)
  -- build an inverse transition table for the whole dfa
  inverse_transtions = {}
  for state in dfa:states():each() do
    for char, to_state in pairs(state.transitions) do
      inverse_transitions[tostring(to_state) .. tostring(char)] = state
    end
  end

  while #queue > 0 do
    partition, symbol = unpack(table.remove(queue))
    new_twins = {}

    -- build a list of states that transition into this partition
    -- on this symbol
    d = Set:new()
    for state in partition:each() do
      from_state = inverse_transitions[tostring(state) .. tostring(symbol)]
      if from_state then d:add(from_state) end
    end

    for state in d:each() do
      needs_split = false
      for s in state.partition:each() do
        if s.transitions[symbol].partition ~= partition then
          needs_split = true
          break
        end
      end

      if needs_split then
        p = state.partition
        new_twins[p] = new_twins[p] or Set:new()
        new_twins[p]:add(state)
        state.partition = new_twins[p]
        p:remove(state)
      end
    end

    for old_part, new_twin in new_twins do
      for sym in all_symbols do
        if queue:contains({old_part, sym}) then queue:add({new_twin, sym})
        elseif 
  end
end



function expensive_minimize(dfa)
  local initial_partitions = {}
  for state in each(dfa:states()) do
    finality = state.final or "NONE"
    initial_partitions[finality] = initial_partitions[finality] or {}
    table.insert(initial_partitions[finality], state)
  end

  local partitions = Set:new()
  local work_queue = Queue:new()
  for regex, states in pairs(initial_partitions) do
    local partition = Set:new(states)
    for i=0,256 do
      work_queue:enqueue({i, partition})
    end
    partitions:add(partition)
  end

  while true do
    if work_queue:isempty() then break end
    local symbol, partition = unpack(work_queue:dequeue())

    local new_partitions = Set:new()
    local remove_partitions = Set:new()

    for source_part in partitions:each() do
      local leads_in = Set:new()
      local leads_not_in = Set:new()
      for part_state in source_part:each() do
        if partition:contains(part_state.transitions[symbol]) then
          leads_in:add(part_state)
        else
          leads_not_in:add(part_state)
        end
      end

      if (not leads_in:isempty()) and (not leads_not_in:isempty()) then
        new_partitions:add(leads_in)
        new_partitions:add(leads_not_in)
        remove_partitions:add(source_part)
      end
    end

    for new_part in new_partitions:each() do
      partitions:add(new_part)
      for i=0,256 do
        work_queue:enqueue({i, new_part})
      end
    end

    for remove_partition in remove_partitions:each() do
      partitions:remove(remove_partition)
    end
  end

  -- partitions are the new states
  -- find the partition that has our original "begin" state in it
  local begin_partition = nil
  local states = {}
  local partition_map = {}
  for partition in partitions:each() do
    states[partition] = FAState:new()
    for state in partition:each() do
      partition_map[state] = partition
      if state.final then
        states[partition].final = state.final
      end
    end
  end

  local minimal_dfa = FA:new()
  minimal_dfa.start = states[partition_map[dfa.start]]
  for partition in partitions:each() do
    for state in partition:each() do
      for char, dest_state in pairs(state.transitions) do
        states[partition].transitions[char] = states[partition_map[dest_state]]
      end
    end
  end

  return minimal_dfa
end


  -- set up an inverse transition table
  -- local inverse_transitions = new_table_with_default(function () return {} end)
  local inverse_transitions = {}
  for state in each(dfa:states()) do
    for int_set, dest_state in pairs(state.transitions) do
      inverse_transitions[dest_state] = inverse_transitions[dest_state] or {}
      inverse_transitions[dest_state][int_set] = state
    end
  end

  -- set up initial blocks
  local work_queue = Queue:new()
  local blocks = Set:new()

  --local initial_blocks = new_table_with_default(function () return {} end)
  local initial_blocks = {}
  for state in each(dfa:states()) do
    local finality = state.final or "NONE"
    initial_blocks[finality] = initial_blocks[finality] or {}
    table.insert(initial_blocks[finality], state)
  end

  for finality, states in pairs(initial_blocks) do
    local block = {states=states, split_by={}}
    for state in each(states) do
      state.block = block
    end
    blocks:add(block)
  end

  for block in each(blocks) do
    for int_set in each(equivalent_regions_for_block(block, inverse_transitions)) do
      work_queue:enqueue({block, int_set})
    end
  end

  local deleted_blocks = Set:new()

  while (not work_queue:isempty()) do
    local block, int_set = unpack(work_queue:dequeue())
    if not deleted_blocks:contains(block) then
    table.insert(block.split_by, int_set)

    print("Splitting by " .. int_set:toasciistring())

    -- what blocks need to be split by this block/int_set?
    local blocks_to_split = Set:new()
    for state in each(block.states) do
      if inverse_transitions[state] then
        local incoming_state = transition_for(inverse_transitions[state], int_set:sampleint())
        if incoming_state then
          print("Block to split: " .. tostring(incoming_state.block))
          blocks_to_split:add(incoming_state.block)
        end
      end
    end

    -- split the necessary blocks
    for block_to_split in each(blocks_to_split) do
      local leads_in = Set:new()
      local leads_not_in = Set:new()
      for state in each(block_to_split.states) do
        local dest_state = state:transition_for(int_set:sampleint())
        if dest_state and dest_state.block == block then
          leads_in:add(state)
        else
          leads_not_in:add(state)
        end
      end

      if (not leads_in:isempty()) and (not leads_not_in:isempty()) then
        -- This block was in fact split.  Physically perform the split.
        local block_leads_in = {states=leads_in:to_array(), split_by={}}
        local block_leads_not_in = {states=leads_in:to_array(), split_by={}}
        blocks:remove(block_to_split)
        deleted_blocks:add(block_to_split)
        blocks:add(block_leads_in)
        blocks:add(block_leads_not_in)

        for state in each(block_leads_in.states) do
          state.block = block_leads_in
        end

        for state in each(block_leads_not_in.states) do
          state.block = block_leads_not_in
        end

        -- Adjust our work queue accordingly.
        for region in each(equivalent_regions_for_block(block_leads_in, inverse_transitions)) do
          local contains = false
          for int_set in each(block_to_split.split_by) do
            if int_set:is_superset(region) then
              contains = true
              break
            end
          end
          if (not contains) then
            work_queue:enqueue({block_leads_in, region})
          end
        end

        for region in each(equivalent_regions_for_block(block_leads_in, inverse_transitions)) do
          work_queue:enqueue({block_leads_not_in, region})
        end
      end
    end
  end
  end

  local states = {}
  for block in blocks:each() do
    states[block] = FAState:new()
    for state in each(block.states) do
      if state.final then
        states[block].final = state.final
      end
    end
  end

  local minimal_dfa = FA:new()
  minimal_dfa.start = states[dfa.start.block]
  for block in blocks:each() do
    for state in each(block.states) do
      for int_set, dest_state in pairs(state.transitions) do
        states[block].transitions[int_set] = states[dest_state.block]
      end
    end
  end

  return minimal_dfa
end


-- It's probably possible to prune this more aggressively, but it's
-- quite difficult to figure out exactly how.  Could revisit here
-- if minimization is more expensive than desired.
function equivalent_regions_for_block(block, inverse_transitions)
  -- Get a list of all blocks that lead in
  local leads_in_blocks = Set:new()
  for state in each(block.states) do
    if inverse_transitions[state] then
      for int_set, source_state in pairs(inverse_transitions[state]) do
        leads_in_blocks:add(source_state.block)
      end
    end
  end

  local int_sets = {}
  for leads_in_block in each(leads_in_blocks) do
    for leads_in_state in each(leads_in_block.states) do
      for int_set, dest_state in pairs(leads_in_state.transitions) do
        table.insert(int_sets, int_set)
      end
    end
  end

  local classes = equivalence_classes(int_sets)
  return classes
end

