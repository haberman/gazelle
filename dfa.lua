
dofile("misc.lua")

function epsilon_closure(state)
  return breadth_first_traversal(state, function (s) return s.transitions["e"] end)
end

-- we as input an array of NFAs, one for each token we want to match simultaneously,
-- and strings describing each token.  So:
-- { {nfa1, "token string 1"},
--   {nfa2, "token string 2", etc} }
function nfas_to_dfa(nfas)
  -- First we need to mark all final states and capture groups with the token string
  for i, nfa_string_pair in ipairs(nfas) do
    nfa, token_string = unpack(nfa_string_pair)

    -- We assign capture groups in order of the left parentheses we encounter
    capture_group_num = 0

    capture_group_stack = Stack:new()

    -- Mark the nfa fragment's final state as the final state for this *token*
    nfa.final.final = token_string

    for state in set_or_array_each(nfa:states()) do
      if state.transitions["("] then
        state.transitions["("] = {state.transitions["("], token_string, capture_group_num}
        capture_group_stack:push(capture_group_num)
        capture_group_num = capture_group_num + 1
      elseif state.transitions["("] then
        state.transitions[")"] = {state.transitions[")"], token_string, capture_group_stack:pop()}
      end
    end
  end

  -- Now combine all the nfas with alternation
  local final_nfa = FA:new()
  final_nfa.start["e"] = {}

  for i, nfa_string_pairs in ipairs(nfas) do
    nfa, token_string = unpack(nfa_string_pair)
    table.insert(final_nfa.start["e"], nfa.start)
    nfa.final["e"] = final_nfa.final
  end

  return nfa_to_dfa(final_nfa)
end

function nfa_to_dfa(nfa)
  -- The sets of NFA states we need to process for outgoing transitions
  queue = Queue:new(epsilon_closure(nfa.start))

  dfa = FA:new()
  -- The DFA states we create from sets of NFA states
  dfa_states = {[queue[1]:hash_key()] = dfa.start}

  while not queue:empty() do
    local nfa_states = queue:dequeue()
    local dfa_state = dfa_states[nfa_states:hash_key()]

    -- Generate a list of symbols that transition out of this set of NFA states.
    -- We could skip this and just iterate over the entire symbol (character)
    -- space, but since we want to support character sets with LARGE character
    -- spaces (eg. Unicode), that would be an expensive way to do things.
    out_symbols = Set:new()
    for nfa_state in nfa_states:each() do
      for symbol, new_state in pairs(nfa_state.transitions) do
        if symbol ~= "e" then out_symbols:add(symbol) end
      end
    end

    -- For each output symbol, generate the list of destination NFA states that
    -- recognizing this symbol could put you in (including epsilon transitions).
    for symbol in out_symbols:each() do
      dest_nfa_states = Set:new()
      for nfa_state in nfa_states:each() do
        if nfa_state.transitions[symbol] then
          for i,dest_nfa_state in ipairs(nfa_state.transitions[symbol]) do
            dest_nfa_states:add(dest_nfa_state)
            dest_nfa_states:add_array(epsilon_closure(dest_nfa_state):to_array())
          end
        end
      end

      -- create a DFA state for this set of NFA states, if one does not
      -- already exist.
      if dfa_states[dest_nfa_states:hash_key()] == nil then

        dfa_state = FAState:new()

        -- If this is a final state for one or more of the nfas, make it an
        -- (appropriately labeled) final state for the dfa
        for nfa_state in nfa_states:each() do
          if nfa_state.final then
            dfa_state.final = dfa_state.final or {}
            table.insert(dfa_state.final, nfa_state.final)
          end
        end

        dfa_states[dest_nfa_states:hash_key()] = dfa_state

        queue:enqueue(dest_nfa_states)
      end

      -- create a transition from the current DFA state into the new one
      dfa_state.transitions[symbol] = dfa_states[dest_nfa_states:hash_key()]
    end
  end

  return dfa
end

function dfa_match(dfa, in_string)
  current_state = dfa.begin
  str_offset = 1
  while current_state.transitions[in_string:byte(str_offset)] do
    current_state = current_state.transitions[in_string:byte(str_offset)]
    str_offset = str_offset + 1
  end
end

