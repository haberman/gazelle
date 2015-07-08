--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  intfa_combine.lua

  Once the lookahead has been calculated, we know what terminal(s)
  each RTN/GLA state is expecting to see.  We use this information to
  build IntFAs that recognize any possible valid token that could
  occur at this point in the input.  We combine and reuse DFAs as much
  as possible -- only when two terminals conflict is it necessary to
  use different DFAs.

--------------------------------------------------------------------]]--

-- Determine what terminals (if any) conflict with each other.
-- In this context, "conflict" means that a string of characters can
-- be interpreted as one or more terminals.
function analyze_conflicts(terminals)
  -- We detect conflicts by combining all the NFAs into a single DFA.
  -- We then observe what states are final to more than one terminal.
  local conflicts = {}
  local nfas = {}
  for name, terminal in pairs(terminals) do
    if type(terminal) == "string" then
      terminal = fa.intfa_for_string(terminal)
    end
    table.insert(nfas, {terminal, name})
  end

  local uber_dfa = nfas_to_dfa(nfas, true)
  for state in each(uber_dfa:states()) do
    if type(state.final) == "table" then  -- more than one terminal ended in this state
      for term1 in each(state.final) do
        for term2 in each(state.final) do
          if term1 ~= term2 then
            conflicts[term1] = conflicts[term1] or Set:new()
            conflicts[term1]:add(term2)
          end
        end
      end
    end
  end

  return conflicts
end

function has_conflicts(conflicts, term_set1, term_set2)
  for term1 in each(term_set1) do
    if conflicts[term1] then
      for conflict in each(conflicts[term1]) do
        if term_set2:contains(conflict) then
          return true, term1, conflict
        end
      end
    end
  end
end

function create_or_reuse_termset_for(terminals, conflicts, termsets, nonterm)
  if has_conflicts(conflicts, terminals, terminals) then
    local has_conflict, c1, c2 = has_conflicts(conflicts, terminals, terminals)
    error(string.format("Can't build DFA inside %s, because terminals %s and %s conflict",
                        nonterm, c1, c2))
  end

  local found_termset = false
  for i, termset in ipairs(termsets) do
    -- will this termset do?  it will if none of our terminals conflict with any of the
    -- existing terminals in this set.
    -- (we can probably compute this faster by pre-computing equivalence classes)
    if not has_conflicts(conflicts, termset, terminals) then
      found_termset = i
      break
    end
  end

  if found_termset == false then
    local new_termset = Set:new()
    table.insert(termsets, new_termset)
    found_termset = #termsets
  end

  -- add all the terminals for this phase of lookahead to the termset we found
  local termset = termsets[found_termset]
  for term in each(terminals) do
    termset:add(term)
  end
  assert(termset:count() > 0)

  return found_termset
end

function intfa_combine(all_terminals, state_term_pairs)
  local conflicts = analyze_conflicts(all_terminals)

  -- For each state in the grammar, create (or reuse) a DFA to run
  -- when we hit that state.
  local termsets = {}
  local intfa_nums = {}
  for state_term_pair in each(state_term_pairs) do
    local state, terms = unpack(state_term_pair)
    assert(terms:count() > 0)
    local nonterm
    if state.rtn == nil then
      nonterm = state.gla.rtn_state.rtn.name
    else
      nonterm = state.rtn.name
    end
    intfa_nums[state] = create_or_reuse_termset_for(terms, conflicts, termsets, nonterm)
  end

  local dfas = OrderedSet:new()
  for termset in each(termsets) do
    local nfas = {}
    for term in each(termset) do
      local target = all_terminals[term]
      assert(target, string.format("No terminal for terminal '%s'", tostring(serialize(term))))
      if type(target) == "string" then
        target = fa.intfa_for_string(target)
      end
      table.insert(nfas, {target, term})
    end
    local dfa = hopcroft_minimize(nfas_to_dfa(nfas))
    dfa.termset = termset
    dfas:add(dfa)
  end

  for state, intfa_num in pairs(intfa_nums) do
    state.intfa = dfas:element_at(intfa_num)
  end

  dfas:sort(function (a, b) return b.termset:count() < a.termset:count() end)

  return dfas
end

-- vim:et:sts=2:sw=2
