--[[--------------------------------------------------------------------

  nfa_to_dfa.lua

  Translate a set of NFAs into a DFA that can recognize any of the
  constituent strings.  This is how we build a lexer that looks for
  all candidate tokens simultaneously.

  Copyright (c) 2007 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

require "data_structures"
require "misc"

function epsilon_closure(state)
  return breadth_first_traversal(state, function(s) return s:transitions_for(fa.e) end)
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

    -- Mark the nfa fragment's final state as the final state for this *token*
    nfa.final.final = token_string
  end

  -- Now combine all the nfas with alternation
  local final_nfa = nfa_construct.alt(nfas)
  return nfa_to_dfa(final_nfa)
end

function new_dfa_state(nfa, nfa_states)
  local dfa_state = nfa:new_state()

  -- If this is a final state for one or more of the nfas, make it an
  -- (appropriately labeled) final state for the dfa
  for nfa_state in nfa_states:each() do
    if nfa_state.final then
      if dfa_state.final and dfa_state.final ~= nfa_state.final then
        error("Ambiguous finality not supported yet!! (" .. tostring(dfa_state.final) .. " and " .. tostring(nfa_state.final .. ")"))
      end
      dfa_state.final = nfa_state.final
    end
  end

  return dfa_state
end

function nfa_to_dfa(nfa)
  -- The sets of NFA states we need to process for outgoing transitions
  local first_nfa_states = epsilon_closure(nfa.start)
  local queue = Queue:new(first_nfa_states)

  local dfa = nfa:new_graph{start = new_dfa_state(nfa, first_nfa_states)}
  -- The DFA states we create from sets of NFA states
  local dfa_states = {[first_nfa_states:hash_key()] = dfa.start}

  while not queue:isempty() do
    local nfa_states = queue:dequeue()
    local dfa_state = dfa_states[nfa_states:hash_key()]

    -- Generate a list of symbols that transition out of this set of NFA states.
    -- We prefer this to iterating over the entire symbol space because it's
    -- vastly more efficient in the case of a large symbol space (eg. Unicode)
    local symbols = nfa:get_outgoing_edge_values(nfa_states)

    -- For each output symbol, generate the list of destination NFA states that
    -- recognizing this symbol could put you in (including epsilon transitions).
    for symbol in each(symbols) do
      local dest_nfa_states = Set:new()
      for nfa_state in nfa_states:each() do
        -- equivalence classes dictate that this character represents what will
        -- happen to ALL characters in the set
        local target_states = nfa_state:transitions_for(symbol)

        if target_states then
          for target_state in each(target_states) do
            dest_nfa_states:add(target_state)
            dest_nfa_states:add_collection(epsilon_closure(target_state):to_array())
          end
        end
      end

      -- create a DFA state for this set of NFA states, if one does not
      -- already exist.
      local dest_dfa_state = dfa_states[dest_nfa_states:hash_key()]
      if dest_dfa_state == nil then
        dest_dfa_state = new_dfa_state(nfa, dest_nfa_states)
        dfa_states[dest_nfa_states:hash_key()] = dest_dfa_state
        queue:enqueue(dest_nfa_states)
      end

      -- create a transition from the current DFA state into the new one
      dfa_state:add_transition(symbol, dest_dfa_state)
    end
  end

  return dfa
end

