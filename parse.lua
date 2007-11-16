
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

  -- for nonterm, rtn in pairs(grammar) do
  --   print(nonterm)
  --   print(rtn)
  -- end

  local decisions
  function my_child_edges(edge, stack)
    return child_edges(edge, stack, grammar, decisions)
  end

  -- For each state in the grammar, create (or reuse) a DFA to run
  -- when we hit that state.
  for nonterm, rtn in pairs(grammar) do
    -- print(nonterm)
    -- print(rtn)
    for state in each(rtn:states()) do
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
        local nfas = {}
        for term, stack in pairs(decisions) do
          local target = attributes.terminals[term]
          if type(target) == "string" then
            target = fa.IntFA:new{string=target}
          end
          table.insert(nfas, {target, term})
        end

        state.dfa = hopcroft_minimize(nfas_to_dfa(nfas))
        state.decisions = decisions
      end
    end
  end

  return grammar, attributes, decisions
end

function write_grammar(infilename, outfilename)
  grammar, attributes, decisions = load_grammar(infilename)

  -- write Bitcode header
  bc_file = bc.File:new(outfilename, "GH")

  bc_file:enter_subblock(bc.BLOCKINFO)
  bc_file:write_unabbreviated_record(bc.SETBID, BC_INTFA)

  bc_intfa_final_state = bc_file:define_abbreviation(bc.LiteralOp:new(BC_INTFA_FINAL_STATE),
                                                     bc.VBROp:new(5), bc.VBROp:new(5))
  bc_intfa_state = bc_file:define_abbreviation(bc.LiteralOp:new(BC_INTFA_STATE), bc.VBROp:new(5))
  bc_intfa_transition = bc_file:define_abbreviation(bc.LiteralOp:new(BC_INTFA_TRANSITION), bc.VBROp:new(8), bc.VBROp:new(6))
  bc_intfa_transition_range = bc_file:define_abbreviation(bc.LiteralOp:new(BC_INTFA_TRANSITION_RANGE), bc.VBROp:new(8), bc.VBROp:new(8), bc.VBROp:new(6))
  bc_file:end_subblock(bc.BLOCKINFO)

  print(string.format("Writing grammar to disk..."))

  local intfas = {}
  local intfa_offsets = {}
  local strings = {}
  local string_offsets = {}

  for name, rtn in pairs(grammar) do
    for rtn_state in each(rtn:states()) do
      if rtn_state.dfa and not intfa_offsets[rtn_state.dfa] then
        table.insert(intfas, rtn_state.dfa)
        intfa_offsets[rtn_state.dfa] = #intfas
      end
    end
  end

  bc_file:enter_subblock(BC_INTFAS)
  for intfa in each(intfas) do
    bc_file:enter_subblock(BC_INTFA)
    local intfa_states = {}
    local intfa_state_offsets = {}
    local intfa_transitions = {}
    local intfa_state_transition_offsets = {}

    --bc_file:enter_subblock(BC_INTFA_STATES)
    for state in each(intfa:states()) do
      intfa_state_offsets[state] = #intfa_states
      table.insert(intfa_states, state)
      local initial_offset = #intfa_transitions
      for edge_val, target_state, properties in state:transitions() do
        for range in edge_val:each_range() do
          table.insert(intfa_transitions, {range, target_state})
        end
      end
      local num_transitions = #intfa_transitions - initial_offset
      if state.final and not string_offsets[state.final] then
        string_offsets[state.final] = #strings
        table.insert(strings, state.final)
      end
      if state.final then
        bc_file:write_abbreviated_record(bc_intfa_final_state, num_transitions, string_offsets[state.final])
      else
        bc_file:write_abbreviated_record(bc_intfa_state, num_transitions)
      end
    end
    --bc_file:end_subblock(BC_INTFA_STATES)

    --bc_file:enter_subblock(BC_INTFA_TRANSITIONS)
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

    --bc_file:end_subblock(BC_INTFA_TRANSITIONS)
    bc_file:end_subblock(BC_INTFA)
  end
  bc_file:end_subblock(BC_INTFAS)

  -- print("Strings:")
  -- for str in each(strings) do
  --   print("   " .. str)
  -- end

  -- for name, rtn in pairs(grammar) do
  --   rtns_offsets[rtn] = #rtns
  --   if not string_offsets[name] then
  --     string_offsets[name] = #strings
  --     table.insert(strings, name)
  --   end

  --   table.insert(rtns, {name, rtn})
  --   for rtn_state in each(rtn:states()) do
  --     rtnstates_offsets[rtn_state] = #rtnstates
  --     table.insert(rtnstates, rtn_state)
  --     if rtn_state.dfa and not intfas_offsets[rtn_state.dfa] then
  --       intfas_offsets[rtn_state.dfa] = #intfas
  --       table.insert(intfas, rtn_state.dfa)
  --       for dfa_state in each(rtn_state.dfa:states()) do
  --         intfastates_offsets[dfa_state] = #intfastates
  --         table.insert(intfastates, dfa_state)
  --         local initial_offset = #intfa_transitions
  --         for edge_val, target_state, properties in dfa_state:transitions() do
  --           for range in edge_val:each_range() do
  --             table.insert(intfa_transitions, {range, target_state})
  --           end
  --         end
  --         intfastate_transitions_for[dfa_state] = {initial_offset, #intfa_transitions - initial_offset}
  --         if dfa_state.final and not string_offsets[dfa_state.final] then
  --           string_offsets[dfa_state.final] = #strings
  --           table.insert(strings, dfa_state.final)
  --         end
  --       end
  --     end

  --     local initial_offset = #rtntransitions
  --     for edge_val, target_state, properties in rtn_state:transitions() do
  --       table.insert(rtntransitions, {edge_val, target_state, properties})
  --     end
  --     rtnstate_transitions_for[rtn_state] = {initial_offset, #rtntransitions - initial_offset}
  --   end
  -- end

  -- print(string.format("%d RTNs, %d states, %d transitions", #rtns, #rtnstates, #rtntransitions))
  --print(string.format("%d IntFAs, %d states, %d transitions", #intfas, #intfastates, #intfa_transitions))
  print(string.format("%d IntFAs", #intfas))
  print(string.format("%d strings", #strings))

end

write_grammar(arg[1], arg[2])
