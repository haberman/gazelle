--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  bytecode.lua

  Code that takes the final optimized parsing structures and emits them
  to bytecode (in Bitcode format).

  Copyright (c) 2007 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

require "bc"

-- See FILEFORMAT for details about what these constants mean
BC_INTFAS = 8
BC_INTFA = 9
BC_STRINGS = 10
BC_RTNS = 11
BC_RTN = 12
BC_GLAS = 13
BC_GLA = 14

BC_INTFA_STATE = 0
BC_INTFA_FINAL_STATE = 1
BC_INTFA_TRANSITION = 2
BC_INTFA_TRANSITION_RANGE = 3

BC_STRING = 0

BC_RTN_INFO = 0
BC_RTN_STATE_WITH_INTFA = 2
BC_RTN_STATE_WITH_GLA = 3
BC_RTN_TRIVIAL_STATE = 4
BC_RTN_TRANSITION_TERMINAL = 5
BC_RTN_TRANSITION_NONTERM = 6

BC_GLA_STATE = 0
BC_GLA_FINAL_STATE = 1
BC_GLA_TRANSITION = 2

if not print_verbose then
  function print_verbose(str)
    print(str)
  end
end

function write_bytecode(grammar, outfilename)
  -- write Bitcode header
  bc_file = bc.File:new(outfilename, "GH")
  abbrevs = define_abbrevs(bc_file)

  -- Obtain linearized representations of all the DFAs from the Grammar object.
  local strings = grammar:get_strings()
  local rtns = grammar:get_flattened_rtn_list()
  local glas = grammar:get_flattened_gla_list()
  local intfas = grammar.master_intfas

  -- emit the strings
  print_verbose(string.format("Writing %d strings...", strings:count()))
  bc_file:enter_subblock(BC_STRINGS)
  for string in each(strings) do
    bc_file:write_abbreviated_record(abbrevs.bc_string, string)
  end
  bc_file:end_subblock(BC_STRINGS)

  -- emit the intfas
  print_verbose(string.format("Writing %d IntFAs...", intfas:count()))
  bc_file:enter_subblock(BC_INTFAS)
  for intfa in each(intfas) do
    emit_intfa(intfa, strings, bc_file, abbrevs)
  end
  bc_file:end_subblock(BC_INTFAS)

  -- emit the GLAs
  print_verbose(string.format("Writing %d GLAs...", glas:count()))
  bc_file:enter_subblock(BC_GLAS)
  for gla in each(glas) do
    emit_gla(gla, strings, rtns, intfas, bc_file, abbrevs)
  end
  bc_file:end_subblock(BC_GLAS)

  -- emit the RTNs
  bc_file:enter_subblock(BC_RTNS)
  print_verbose(string.format("Writing %d RTNs...", rtns:count()))
  for name, rtn in each(rtns) do
    emit_rtn(name, rtn, rtns, glas, intfas, strings, bc_file, abbrevs)
  end
  bc_file:end_subblock(BC_RTNS)

end


function emit_intfa(intfa, strings, bc_file, abbrevs)
  bc_file:enter_subblock(BC_INTFA)

  local intfa_state_offsets = {}
  local intfa_transitions = {}

  -- order the states such that the start state is emitted first
  local states = intfa:states()
  states:remove(intfa.start)
  states = states:to_array()
  table.insert(states, 1, intfa.start)

  -- do a first pass over the states that records their order and builds
  -- each state's list of transitions.
  local state_transitions = {}
  for i, state in ipairs(states) do
    intfa_state_offsets[state] = i - 1

    state_transitions[state] = {}
    for edge_val, target_state, properties in state:transitions() do
      for range in edge_val:each_range() do
        table.insert(state_transitions[state], {range, target_state})
      end
    end

    -- sort the transitions into a stable order, to make the output
    -- more deterministic.
    table.sort(state_transitions[state], function (a, b) return a[1].low < b[1].low end)

    -- add this state's transitions to the global list of transitions for the IntFA
    for t in each(state_transitions[state])
      do table.insert(intfa_transitions, t)
    end
  end

  print_verbose(string.format("  %d states, %d transitions", #states, #intfa_transitions))

  -- emit the states
  for state in each(states) do
    if state.final then
      bc_file:write_abbreviated_record(abbrevs.bc_intfa_final_state,
                                       #state_transitions[state],
                                       strings:offset_of(state.final))
    else
      bc_file:write_abbreviated_record(abbrevs.bc_intfa_state, #state_transitions[state])
    end
  end

  -- emit the transitions
  for transition in each(intfa_transitions) do
    local range, target_state = unpack(transition)
    target_state_offset = intfa_state_offsets[target_state]
    if range.low == range.high then
      bc_file:write_abbreviated_record(abbrevs.bc_intfa_transition, range.low, target_state_offset)
    else
      local high = range.high
      if high == math.huge then high = 255 end  -- temporary ASCII-specific hack
      bc_file:write_abbreviated_record(abbrevs.bc_intfa_transition_range, range.low, high, target_state_offset)
    end
  end

  bc_file:end_subblock(BC_INTFA)
end

function emit_gla(gla, strings, rtns, intfas, bc_file, abbrevs)
  bc_file:enter_subblock(BC_GLA)

  local states = OrderedSet:new()
  states:add(gla.start)
  for state in each(gla:states()) do
    if state ~= gla.start then
      states:add(state)
    end
  end

  -- emit states
  for state in each(states) do
    if state.final then
      -- figure out the offset of the RTN transition this GLA final state implies.
      local ordered_rtn = rtns:get(gla.rtn_state.rtn.name)
      local transitions = ordered_rtn.transitions[gla.rtn_state]
      local transition_offset = nil
      for i=1,#transitions do
        if transitions[i][1] == state.final[1] and transitions[i][2] == state.final[2] then
          transition_offset = i
          break
        end
      end

      if transition_offset == nil then
        error("GLA final state indicated a state that was not found in the RTN state.")
      end
      bc_file:write_abbreviated_record(abbrevs.bc_gla_final_state, transition_offset)
    else
      bc_file:write_abbreviated_record(abbrevs.bc_gla_state,
                                       intfas:offset_of(state.intfa),
                                       state:num_transitions())
    end
  end

  -- emit transitions
  for state in each(states) do
    for edge_val, dest_state in state:transitions() do
      bc_file:write_abbreviated_record(abbrevs.bc_gla_transition,
                                       strings:offset_of(edge_val),
                                       states:offset_of(dest_state))
    end
  end

  bc_file:end_subblock(BC_GLA)
end

function emit_rtn(name, rtn, rtns, glas, intfas, strings, bc_file, abbrevs)
  -- emit RTN name
  bc_file:enter_subblock(BC_RTN)
  bc_file:write_abbreviated_record(abbrevs.bc_rtn_info, strings:offset_of(name), rtn.slot_count)

  -- emit states
  for state in each(rtn.states) do
    local is_final
    if state.final then
      is_final = 1
    else
      is_final = 0
    end

    if state.gla then
      bc_file:write_abbreviated_record(abbrevs.bc_rtn_state_with_gla,
                                       #rtn.transitions[state],
                                       is_final,
                                       glas:offset_of(state.gla))
    elseif state.intfa then
      bc_file:write_abbreviated_record(abbrevs.bc_rtn_state_with_intfa,
                                       #rtn.transitions[state],
                                       is_final,
                                       intfas:offset_of(state.intfa))
    else
      bc_file:write_abbreviated_record(abbrevs.bc_rtn_trivial_state,
                                       #rtn.transitions[state],
                                       is_final)
    end
  end

  -- emit transitions
  for state in each(rtn.states) do
    for transition in each(rtn.transitions[state]) do
      local edge_val, dest_state, properties = unpack(transition)
      if fa.is_nonterm(edge_val) then
        bc_file:write_abbreviated_record(abbrevs.bc_rtn_transition_nonterm,
                                         rtns:offset_of_key(edge_val.name),
                                         rtn.states:offset_of(dest_state),
                                         strings:offset_of(properties.name),
                                         properties.slotnum-1)
      else
        bc_file:write_abbreviated_record(abbrevs.bc_rtn_transition_terminal,
                                         strings:offset_of(edge_val),
                                         rtn.states:offset_of(dest_state),
                                         strings:offset_of(properties.name),
                                         properties.slotnum-1)
      end
    end
  end

  bc_file:end_subblock(BC_RTN)
end


function define_abbrevs(bc_file)
  abbrevs = {}

  -- Enter a BLOCKINFO record to define abbreviations for all our records.
  -- See FILEFORMAT for a description of what all the record types mean.
  bc_file:enter_subblock(bc.BLOCKINFO)

  -- IntFA abbreviations
  bc_file:write_unabbreviated_record(bc.SETBID, BC_INTFA)

  abbrevs.bc_intfa_final_state = bc_file:define_abbreviation(4,
                                      bc.LiteralOp:new(BC_INTFA_FINAL_STATE),
                                      bc.VBROp:new(5),
                                      bc.VBROp:new(5))

  abbrevs.bc_intfa_state = bc_file:define_abbreviation(5,
                                      bc.LiteralOp:new(BC_INTFA_STATE),
                                      bc.VBROp:new(5))

  abbrevs.bc_intfa_transition = bc_file:define_abbreviation(6,
                                      bc.LiteralOp:new(BC_INTFA_TRANSITION),
                                      bc.VBROp:new(8),
                                      bc.VBROp:new(6))

  abbrevs.bc_intfa_transition_range = bc_file:define_abbreviation(7,
                                      bc.LiteralOp:new(BC_INTFA_TRANSITION_RANGE),
                                      bc.VBROp:new(8),
                                      bc.VBROp:new(8),
                                      bc.VBROp:new(6))

  -- Strings abbreviations
  bc_file:write_unabbreviated_record(bc.SETBID, BC_STRINGS)

  abbrevs.bc_string = bc_file:define_abbreviation(4,
                                      bc.LiteralOp:new(BC_STRING),
                                      bc.ArrayOp:new(bc.FixedOp:new(7)))

  -- RTN abbreviations
  bc_file:write_unabbreviated_record(bc.SETBID, BC_RTN)

  abbrevs.bc_rtn_info = bc_file:define_abbreviation(4,
                                      bc.LiteralOp:new(BC_RTN_INFO),
                                      bc.VBROp:new(6),
                                      bc.VBROp:new(4))

  abbrevs.bc_rtn_state_with_intfa = bc_file:define_abbreviation(5,
                                      bc.LiteralOp:new(BC_RTN_STATE_WITH_INTFA),
                                      bc.VBROp:new(4),
                                      bc.FixedOp:new(1),
                                      bc.VBROp:new(4))

  abbrevs.bc_rtn_state_with_gla = bc_file:define_abbreviation(6,
                                      bc.LiteralOp:new(BC_RTN_STATE_WITH_GLA),
                                      bc.VBROp:new(4),
                                      bc.FixedOp:new(1),
                                      bc.VBROp:new(4))

  abbrevs.bc_rtn_trivial_state = bc_file:define_abbreviation(7,
                                      bc.LiteralOp:new(BC_RTN_TRIVIAL_STATE),
                                      bc.FixedOp:new(1),
                                      bc.FixedOp:new(1))

  abbrevs.bc_rtn_transition_terminal = bc_file:define_abbreviation(8,
                                      bc.LiteralOp:new(BC_RTN_TRANSITION_TERMINAL),
                                      bc.VBROp:new(6),
                                      bc.VBROp:new(5),
                                      bc.VBROp:new(5),
                                      bc.VBROp:new(4))

  abbrevs.bc_rtn_transition_nonterm = bc_file:define_abbreviation(9,
                                      bc.LiteralOp:new(BC_RTN_TRANSITION_NONTERM),
                                      bc.VBROp:new(6),
                                      bc.VBROp:new(5),
                                      bc.VBROp:new(5),
                                      bc.VBROp:new(4))

  -- GLA abbreviations
  bc_file:write_unabbreviated_record(bc.SETBID, BC_GLA)

  abbrevs.bc_gla_state = bc_file:define_abbreviation(4,
                                      bc.LiteralOp:new(BC_GLA_STATE),
                                      bc.VBROp:new(4),
                                      bc.VBROp:new(4))

  abbrevs.bc_gla_final_state = bc_file:define_abbreviation(5,
                                      bc.LiteralOp:new(BC_GLA_FINAL_STATE),
                                      bc.VBROp:new(4))

  abbrevs.bc_gla_transition = bc_file:define_abbreviation(6,
                                      bc.LiteralOp:new(BC_GLA_TRANSITION),
                                      bc.VBROp:new(4),
                                      bc.VBROp:new(4))

  bc_file:end_subblock(bc.BLOCKINFO)

  return abbrevs
end

-- vim:et:sts=2:sw=2

