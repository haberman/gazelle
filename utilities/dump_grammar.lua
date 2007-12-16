--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  dump_grammar.lua

  This is a utility for dumping graphs that allow you to visualize a
  compiled grammar.  The output files are in dot format, suitable for
  processing with graphviz.

  Copyright (c) 2007 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--
require "bc_constants"
--require "sketches/pp"
require "bc_read_stream"

function escape(str)
  return str:gsub("[\"\\]", "\\%1")
end

function escape_char(int)
  local str
  if int == string.byte("\n") then
    str = "\\n"
  elseif int == string.byte("\t") then
    str = "\\t"
  elseif int == string.byte("\r") then
    str = "\\r"
  elseif int < 32 or int > 126 then
    str = string.format("\\%o", int)
  else
    str = string.char(int)
  end
  return escape(str)
end

function read_intfa(infile, outfile, strings)
  outfile:write("digraph untitled {\n")
  local states_num_transitions = {}
  local transition_state_num = 1
  local transition_num = 1
  local extra_label = "Begin"
  while true do
    local val = {infile:next_record()}
    if val[1] == "endblock" then break end
    if val[1] ~= "data" then error("Got unexpected record type " .. val[1]) end
    if val[2] == BC_INTFA_STATE then
      table.insert(states_num_transitions, val[3])
      outfile:write(string.format('  "%d" [label="%s" peripheries=1]\n', #states_num_transitions, extra_label))
    elseif val[2] == BC_INTFA_FINAL_STATE then
      table.insert(states_num_transitions, val[3])
      outfile:write(string.format('  "%d" [label="%s %s" peripheries=2]\n', #states_num_transitions, escape(strings[val[4]+1]), extra_label))
    elseif val[2] == BC_INTFA_TRANSITION then
      local str = string.format('  "%d" -> "%d" [label="%s"]\n', transition_state_num, val[4]+1, escape_char(val[3]))
      outfile:write(str)
    elseif val[2] == BC_INTFA_TRANSITION_RANGE then
      local str = string.format('  "%d" -> "%d" [label="%s-%s"]\n', transition_state_num, val[5]+1, escape_char(val[3]), escape_char(val[4]))
      outfile:write(str)
    end
    if val[2] == BC_INTFA_TRANSITION or val[2] == BC_INTFA_TRANSITION_RANGE then
      transition_num = transition_num + 1
      while transition_state_num <= #states_num_transitions and transition_num > states_num_transitions[transition_state_num] do
        transition_num = 1
        transition_state_num = transition_state_num + 1
      end
    end
    extra_label = ""
  end
  outfile:write("}\n")
end

function read_rtn(infile, outfile, strings, rtn_names)
  outfile:write("digraph untitled {\n")
  local states_num_transitions = {}
  local transition_state_num = 1
  local transition_num = 1
  local extra_label = "Begin"
  while true do
    local val = {infile:next_record()}
    --print(serialize(val))
    if val[1] == "endblock" then break end
    if val[1] ~= "data" then error("Got unexpected record type " .. val[1]) end
    if val[2] == BC_RTN_STATE then
      table.insert(states_num_transitions, val[3])
      local peripheries = 1 + val[5]
      outfile:write(string.format('  "%d" [label="%s\\nIntFA: %d" peripheries=%d]\n', #states_num_transitions, extra_label, val[4]+1, peripheries))
    elseif val[2] == BC_RTN_TRANSITION_TERMINAL then
      local str = string.format('  "%d" -> "%d" [label="%s"]\n', transition_state_num, val[4]+1, escape(strings[val[3]+1]))
      outfile:write(str)
    elseif val[2] == BC_RTN_TRANSITION_NONTERM then
      local str = string.format('  "%d" -> "%d" [label="<%s>"]\n', transition_state_num, val[4]+1, escape(strings[rtn_names[val[3]+1]]))
      outfile:write(str)
    elseif val[2] == BC_RTN_DECISION then
    elseif val[2] == BC_RTN_IGNORE then
    else
      error("Invalid transition type! " .. tostring(val[2]))
    end
    if val[2] == BC_RTN_TRANSITION_TERMINAL or val[2] == BC_RTN_TRANSITION_NONTERM or val[2] == BC_RTN_DECISION then
      transition_num = transition_num + 1
      while transition_state_num <= #states_num_transitions and transition_num > states_num_transitions[transition_state_num] do
        transition_num = 1
        transition_state_num = transition_state_num + 1
      end
    end
    extra_label = ""
  end
  outfile:write("}\n")
end

-- do a first pass to get all the RTN names
local bc_file = bc_read_stream.open(arg[1])
local rtn_names = {}
while true do
  local val = {bc_file:next_record()}
  if val[1] == nil then break end
  if val[1] == "startblock" and val[2] == BC_RTN then
    val = {bc_file:next_record()}
    table.insert(rtn_names, val[3]+1)
  end
end


local bc_file = bc_read_stream.open(arg[1])
local intfa_num = 1
local strings = {}

while true do
  local val = {bc_file:next_record()}
  if val[1] == nil then break end
  if val[1] == "startblock" and val[2] == BC_STRINGS then
    val = {bc_file:next_record()}
    while val[1] ~= "endblock" do
      table.remove(val, 1)
      table.remove(val, 1)
      table.insert(strings, string.char(unpack(val)))
      val = {bc_file:next_record()}
    end
    -- print(serialize(strings))
  elseif val[1] == "startblock" and val[2] == BC_INTFA then
    filename = string.format("%d.dot", intfa_num)
    print(string.format("Writing %s...", filename))
    read_intfa(bc_file, io.open(filename, "w"), strings)
    intfa_num = intfa_num + 1
  elseif val[1] == "startblock" and val[2] == BC_RTN then
    local val = {bc_file:next_record()}
    filename = string.format("%s.dot", strings[val[3]+1])
    print(string.format("Writing %s...", filename))
    read_rtn(bc_file, io.open(filename, "w"), strings, rtn_names)
  end
end

