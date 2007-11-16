
require "bc_lua"
require "bc_constants"
require "sketches/pp"

function escape(str)
  return str:gsub("[\"\\]", "\\%1")
end

function read_intfa(infile, outfile, strings)
  outfile:write("digraph untitled {\n")
  local states_num_transitions = {}
  local transition_state_num = 1
  local transition_num = 1
  while true do
    local val = {bc_lua.next_record(infile)}
    if val[1] == "endblock" then break end
    if val[1] ~= "data" then error("Got unexpected record type " .. val[1]) end
    if val[2] == BC_INTFA_STATE then
      table.insert(states_num_transitions, val[3])
      outfile:write(string.format('  "%d" [label="" peripheries=1]\n', #states_num_transitions))
    elseif val[2] == BC_INTFA_FINAL_STATE then
      table.insert(states_num_transitions, val[3])
      outfile:write(string.format('  "%d" [label="%s" peripheries=2]\n', #states_num_transitions, strings[val[4]+1]))
    elseif val[2] == BC_INTFA_TRANSITION then
      local str = string.format('  "%d" -> "%d" [label="%s"]\n', transition_state_num, val[4]+1, escape(string.char(val[3])))
      outfile:write(str)
    elseif val[2] == BC_INTFA_TRANSITION_RANGE then
      local str = string.format('  "%d" -> "%d" [label="%s-%s"]\n', transition_state_num, val[5]+1, escape(string.char(val[3])), escape(string.char(val[4])))
      outfile:write(str)
    end
    if val[2] == BC_INTFA_TRANSITION or val[2] == BC_INTFA_TRANSITION_RANGE then
      transition_num = transition_num + 1
      if transition_num > states_num_transitions[transition_state_num] then
        transition_num = 1
        transition_state_num = transition_state_num + 1
      end
    end
  end
  outfile:write("}")
end

local bc_file = bc_lua.open(arg[1])
local intfa_num = 1
local strings = {}

while true do
  local val = {bc_lua.next_record(bc_file)}
  if val[1] == nil then break end
  if val[1] == "startblock" and val[2] == BC_STRINGS then
    val = {bc_lua.next_record(bc_file)}
    while val[1] ~= "endblock" do
      table.remove(val, 1)
      table.remove(val, 1)
      table.insert(strings, string.char(unpack(val)))
      val = {bc_lua.next_record(bc_file)}
    end
    print(serialize(strings))
  elseif val[1] == "startblock" and val[2] == BC_INTFA then
    filename = string.format("%d.dot", intfa_num)
    print(string.format("Writing %s...", filename))
    read_intfa(bc_file, io.open(filename, "w"), strings)
    intfa_num = intfa_num + 1
  end
end

