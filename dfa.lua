
dofile("misc.lua")

-- We treat'(' and ')' (begin and end capture group) as epsilons, but also
-- add them to a list that we return alongside the simple list of states.
function epsilon_closure(state)
  local begin_groups = {}
  local end_groups = {}

  -- TODO: this is messy: separate concerns by having the "children" function be
  -- separate from the "run this for every node" function
  local children_func = function(s)
    local children = s.transitions["e"]
    if s.transitions["("] then
      table.insert(begin_groups, s.transitions["("])
      children:add(s.transitions["("][3])
    end
    if s.transitions[")"] then
      table.insert(end_groups, s.transitions[")"])
      children:add(s.transitions[")"][3])
    end
    return children
  end

  local nodes = breadth_first_traversal(state, children_func)

  return nodes, begin_groups, end_groups
end

-- we as input an array of NFAs, one for each token we want to match simultaneously,
-- and strings describing each token.  So:
-- { {nfa1, "token string 1"},
--   {nfa2, "token string 2", etc} }
function nfas_to_dfa(nfa_string_pairs)
  -- First we need to mark all final states and capture groups with the token string
  local nfas = {}

  for i, nfa_string_pair in ipairs(nfa_string_pairs) do
    local nfa, token_string = unpack(nfa_string_pair)
    table.insert(nfas, nfa)

    -- We assign capture groups in order of the left parentheses we encounter
    capture_group_num = 0

    capture_group_stack = Stack:new()

    -- Mark the nfa fragment's final state as the final state for this *token*
    nfa.final.final = token_string

    for state in set_or_array_each(nfa:states()) do
      if state.transitions["("] then
        state.transitions["("] = {token_string, capture_group_num, state.transitions["("]}
        capture_group_stack:push(capture_group_num)
        capture_group_num = capture_group_num + 1
      elseif state.transitions["("] then
        state.transitions[")"] = { token_string, capture_group_stack:pop(), state.transitions[")"]}
      end
    end
  end

  -- Now combine all the nfas with alternation
  local final_nfa = nfa_alt(nfas)
  return nfa_to_dfa(final_nfa)
end

function new_dfa_state(nfa_states, begin_groups, end_groups)
  local dfa_state = FAState:new()

  -- If this is a final state for one or more of the nfas, make it an
  -- (appropriately labeled) final state for the dfa
  for nfa_state in nfa_states:each() do
    if nfa_state.final then
      if dfa_state.final then print("Ambiguous finality not supported yet!!") end
      dfa_state.final = nfa_state.final
    end
  end

  -- If there are any begin or end groups, note that in the dfa state as well.
  dfa_state.begin_groups = begin_groups
  dfa_state.end_groups   = end_groups

  return dfa_state
end

function nfa_to_dfa(nfa)
  -- The sets of NFA states we need to process for outgoing transitions
  local first_nfa_states, begin_groups, end_groups = epsilon_closure(nfa.start)
  local queue = Queue:new(first_nfa_states)

  local dfa = FA:new{start = new_dfa_state(first_nfa_states, begin_groups, end_groups)}
  -- The DFA states we create from sets of NFA states
  local dfa_states = {[first_nfa_states:hash_key()] = dfa.start}

  while not queue:isempty() do
    local nfa_states = queue:dequeue()
    local dfa_state = dfa_states[nfa_states:hash_key()]

    -- Generate a list of symbols that transition out of this set of NFA states.
    -- We could skip this and just iterate over the entire symbol (character) space
    -- but we want to avoid doing anything that is O(the character space), so that
    -- we can support LARGE character spaces without flinching.
    local out_symbols = Set:new()
    for nfa_state in nfa_states:each() do
      for symbol, new_state in pairs(nfa_state.transitions) do
        if symbol ~= "e" then out_symbols:add(symbol) end
      end
    end

    -- For each output symbol, generate the list of destination NFA states that
    -- recognizing this symbol could put you in (including epsilon transitions).
    for symbol in out_symbols:each() do
      local dest_nfa_states = Set:new()
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
      local dest_dfa_state = dfa_states[dest_nfa_states:hash_key()]
      if dest_dfa_state == nil then
        dest_dfa_state = new_dfa_state(dest_nfa_states, begin_groups, end_groups)
        dfa_states[dest_nfa_states:hash_key()] = dest_dfa_state
        queue:enqueue(dest_nfa_states)
      end

      -- create a transition from the current DFA state into the new one
      dfa_state.transitions[symbol] = dest_dfa_state
    end
  end

  return dfa
end

function dfa_match(dfa, in_string)
  local current_state = dfa.begin
  local str_offset = 1
  while current_state.transitions[in_string:byte(str_offset)] do
    current_state = current_state.transitions[in_string:byte(str_offset)]
    str_offset = str_offset + 1
  end
end

