
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

