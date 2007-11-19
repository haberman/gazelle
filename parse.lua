
require "rtn"
require "bc"
require "bc_constants"

--print(serialize(attributes.ignore))

function child_edges(edge, stack, grammar, decisions)
  if type(edge) == "table" and edge.class == fa.NonTerm then
    local child_edges = {}
    for edge_val in grammar[edge.name].start:transitions() do
      table.insert(child_edges, edge_val)
    end
    return child_edges
  else
    local str_or_regex
    if type(edge) == "table" then
      str_or_regex = edge.properties.string
    else
      str_or_regex = edge
    end

    decisions[str_or_regex] = stack:to_array()
  end
end

-- require "sketches/regex_debug"
-- require "sketches/pp"

Ignore = {name="Ignore"}

function load_grammar(file)
  -- First read grammar file

  local grm = io.open(file, "r")
  local grm_str = grm:read("*a")

  local grammar, attributes = parse_grammar(CharStream:new(grm_str))

  -- First, determine what terminals (if any) conflict with each other.
  -- In this context, "conflict" means that a string of characters can
  -- be interpreted as one or more terminals.
  local conflicts = {}
  do
    local nfas = {}
    for name, terminal in pairs(attributes.terminals) do
      if type(terminal) == "string" then
        terminal = fa.IntFA:new{string=terminal}
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
  end

  -- For each state in the grammar, create (or reuse) a DFA to run
  -- when we hit that state.
  local dfas = {}

  function has_conflicts(conflicts, dfa, decisions)
    for term, stack in pairs(decisions) do
      if conflicts[term] then
        for conflict in each(conflicts[term]) do
          if dfa:contains(conflict) then
            return true
          end
        end
      end
    end
  end

  for nonterm, rtn in pairs(grammar) do
    -- print(nonterm)
    -- print(rtn)
    for state in each(rtn:states()) do
      local decisions
      function my_child_edges(edge, stack)
        return child_edges(edge, stack, grammar, decisions)
      end

      local transition_num = 0
      decisions = {}
      if state:num_transitions() > 0 then
        for edge_val, target_state in state:transitions() do
          transition_num = transition_num + 1
          depth_first_traversal(edge_val, my_child_edges)
        end

        -- add "ignore" decisions
        if attributes.ignore[nonterm] then
          for ignore in each(attributes.ignore[nonterm]) do
            decisions[ignore] = Ignore
          end
        end

        -- print("Inside " .. nonterm .. ", state=" .. tostring(state) .. "...")
        -- print(serialize(decisions))

        -- We now have a list of terminals we want to find when we are in this RTN
        -- state.  Now get a DFA that will match all of them, either by creating
        -- a new DFA or by finding an existing one that will work (without conflicting
        -- with any of our terminals).
        local found_dfa = false
        for i, dfa in ipairs(dfas) do
          -- will this dfa do?  it will if none of our terminals conflict with any of the
          -- existing terminals in this dfa.
          -- (we can probably compute this faster by pre-computing equivalence classes)
          if not has_conflicts(conflicts, dfa, decisions) then
            found_dfa = i
            break
          end
        end

        if found_dfa == false then
          new_dfa = Set:new()
          table.insert(dfas, new_dfa)
          found_dfa = #dfas
        end

        -- add all the terminals for this state to the dfa we found
        for term, stack in pairs(decisions) do
          -- print(serialize(decisions))
          dfas[found_dfa]:add(term)
        end

        --print(serialize(found_dfa))
        state.dfa = found_dfa
        state.decisions = decisions
      end
    end
  end

  local real_dfas = {}
  for dfa in each(dfas) do
    local nfas = {}
    for term in each(dfa) do
      local target = attributes.terminals[term]
      if type(target) == "string" then
        target = fa.IntFA:new{string=target}
      end
      table.insert(nfas, {target, term})
    end
    local real_dfa = hopcroft_minimize(nfas_to_dfa(nfas))
    table.insert(real_dfas, real_dfa)
  end

  return grammar, attributes, decisions, real_dfas
end

function write_grammar(infilename, outfilename)
  local grammar, attributes, decisions, intfas = load_grammar(infilename)

  -- write Bitcode header
  bc_file = bc.File:new(outfilename, "GH")

  bc_file:enter_subblock(bc.BLOCKINFO)
  bc_file:write_unabbreviated_record(bc.SETBID, BC_INTFA)

  bc_intfa_final_state = bc_file:define_abbreviation(4, bc.LiteralOp:new(BC_INTFA_FINAL_STATE),
                                                     bc.VBROp:new(5), bc.VBROp:new(5))
  bc_intfa_state = bc_file:define_abbreviation(5, bc.LiteralOp:new(BC_INTFA_STATE), bc.VBROp:new(5))
  bc_intfa_transition = bc_file:define_abbreviation(6, bc.LiteralOp:new(BC_INTFA_TRANSITION), bc.VBROp:new(8), bc.VBROp:new(6))
  bc_intfa_transition_range = bc_file:define_abbreviation(7, bc.LiteralOp:new(BC_INTFA_TRANSITION_RANGE), bc.VBROp:new(8), bc.VBROp:new(8), bc.VBROp:new(6))

  bc_file:write_unabbreviated_record(bc.SETBID, BC_STRINGS)
  bc_string = bc_file:define_abbreviation(4, bc.LiteralOp:new(BC_STRING), bc.ArrayOp:new(bc.FixedOp:new(7)))

  bc_file:write_unabbreviated_record(bc.SETBID, BC_RTN)
  bc_rtn_name = bc_file:define_abbreviation(4, bc.LiteralOp:new(BC_RTN_NAME), bc.VBROp:new(6))
  bc_rtn_state = bc_file:define_abbreviation(5, bc.LiteralOp:new(BC_RTN_STATE), bc.VBROp:new(4), bc.VBROp:new(4), bc.FixedOp:new(1))
  bc_rtn_transition_terminal = bc_file:define_abbreviation(6, bc.LiteralOp:new(BC_RTN_TRANSITION_TERMINAL), bc.VBROp:new(6), bc.VBROp:new(5), bc.VBROp:new(5), bc.VBROp:new(4))
  bc_rtn_transition_nonterm = bc_file:define_abbreviation(7, bc.LiteralOp:new(BC_RTN_TRANSITION_NONTERM), bc.VBROp:new(6), bc.VBROp:new(5), bc.VBROp:new(5), bc.VBROp:new(4))

  bc_file:end_subblock(bc.BLOCKINFO)

  print(string.format("Writing grammar to disk..."))

  local intfa_offsets = {}
  local strings = {}
  local string_offsets = {}

  -- gather a list of all the intfas
  -- for name, rtn in pairs(grammar) do
  --   for rtn_state in each(rtn:states()) do
  --     if rtn_state.dfa and not intfa_offsets[rtn_state.dfa] then
  --       table.insert(intfas, rtn_state.dfa)
  --       intfa_offsets[rtn_state.dfa] = #intfas
  --     end
  --   end
  -- end

  -- gather a list of all the strings from intfas
  for intfa in each(intfas) do
    for state in each(intfa:states()) do
      if state.final and not string_offsets[state.final] then
        string_offsets[state.final] = #strings
        table.insert(strings, state.final)
      end
    end
  end

  -- build an ordered list of RTNs and gather the strings from them
  local rtns = {{attributes.start, grammar[attributes.start]}}
  local rtns_offsets = {}
  rtns_offsets[grammar[attributes.start]] = 0
  for name, rtn in pairs(grammar) do
    if name ~= attributes.start then
      rtns_offsets[rtn] = #rtns
      if not string_offsets[name] then
        string_offsets[name] = #strings
        table.insert(strings, name)
      end

      table.insert(rtns, {name, rtn})

      for rtn_state in each(rtn:states()) do
        for edge_val, target_state, properties in rtn_state:transitions() do
          if properties and not string_offsets[properties.name] then
            string_offsets[properties.name] = #strings
            table.insert(strings, properties.name)
          end
        end
      end
    end
  end

  -- emit the strings
  bc_file:enter_subblock(BC_STRINGS)
  for string in each(strings) do
    bc_file:write_abbreviated_record(bc_string, string)
  end
  bc_file:end_subblock(BC_STRINGS)

  -- emit the intfas
  bc_file:enter_subblock(BC_INTFAS)
  for intfa in each(intfas) do
    bc_file:enter_subblock(BC_INTFA)
    local intfa_state_offsets = {}
    local intfa_transitions = {}

    -- make sure the start state is emitted first
    local states = intfa:states()
    states:remove(intfa.start)
    states = states:to_array()
    table.insert(states, 1, intfa.start)
    for i, state in ipairs(states) do
      intfa_state_offsets[state] = i - 1
      local initial_offset = #intfa_transitions
      for edge_val, target_state, properties in state:transitions() do
        for range in edge_val:each_range() do
          table.insert(intfa_transitions, {range, target_state})
        end
      end
      local num_transitions = #intfa_transitions - initial_offset
      if state.final then
        bc_file:write_abbreviated_record(bc_intfa_final_state, num_transitions, string_offsets[state.final])
      else
        bc_file:write_abbreviated_record(bc_intfa_state, num_transitions)
      end
    end

    for transition in each(intfa_transitions) do
      local range, target_state = unpack(transition)
      target_state_offset = intfa_state_offsets[target_state]
      if range.low == range.high then
        bc_file:write_abbreviated_record(bc_intfa_transition, range.low, target_state_offset)
      else
        if range.high == math.huge then range.high = 255 end  -- temporary ASCII-specific hack
        bc_file:write_abbreviated_record(bc_intfa_transition_range, range.low, range.high, target_state_offset)
      end
    end

    bc_file:end_subblock(BC_INTFA)
  end
  bc_file:end_subblock(BC_INTFAS)

  -- emit the RTNs
  bc_file:enter_subblock(BC_RTNS)
  for name_rtn_pair in each(rtns) do
    local name, rtn = unpack(name_rtn_pair)
    bc_file:enter_subblock(BC_RTN)
    bc_file:write_abbreviated_record(bc_rtn_name, string_offsets[name])

    local rtn_states = {}
    local rtn_state_offsets = {}
    local rtn_transitions = {}

    -- make sure the start state is emitted first
    local states = rtn:states()
    states:remove(rtn.start)
    states = states:to_array()
    table.insert(states, 1, rtn.start)
    for i, rtn_state in pairs(states) do
      rtn_state_offsets[rtn_state] = i - 1
      local initial_offset = #rtn_transitions
      for edge_val, target_state, properties in rtn_state:transitions() do
        table.insert(rtn_transitions, {edge_val, target_state, properties})
      end
      local num_transitions = #rtn_transitions - initial_offset
      local is_final = 0
      if rtn_state.final then is_final = 1 end
      -- states don't have an associated DFA if there are no outgoing transitions
      rtn_state.dfa = rtn_state.dfa or 1
      bc_file:write_abbreviated_record(bc_rtn_state, num_transitions, rtn_state.dfa - 1, is_final)
    end

    for transition in each(rtn_transitions) do
      local edge_val, target_state, properties = unpack(transition)
      target_state_offset = rtn_state_offsets[target_state]
      if type(edge_val) == "table" and edge_val.class == fa.NonTerm then
        bc_file:write_abbreviated_record(bc_rtn_transition_nonterm, rtns_offsets[grammar[edge_val.name]],
                                         rtn_state_offsets[target_state], string_offsets[properties.name],
                                         properties.slotnum)
      else
        bc_file:write_abbreviated_record(bc_rtn_transition_terminal, string_offsets[edge_val],
                                         rtn_state_offsets[target_state], string_offsets[properties.name],
                                         properties.slotnum)
      end
    end
    bc_file:end_subblock(BC_RTN)

    -- TODO: decisions
  end
  bc_file:end_subblock(BC_RTNS)

  -- print(string.format("%d RTNs, %d states, %d transitions", #rtns, #rtnstates, #rtntransitions))
  --print(string.format("%d IntFAs, %d states, %d transitions", #intfas, #intfastates, #intfa_transitions))
  print(string.format("%d IntFAs", #intfas))
  print(string.format("%d strings", #strings))

end

write_grammar(arg[1], arg[2])
