
dofile("data_structures.lua")

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

