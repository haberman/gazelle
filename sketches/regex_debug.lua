
dofile("sketches/pp.lua")

-- function NFA:dump_dot()
--   local str = "digraph untitled {\n"
--   local seen = {}
--   local queue = {self.start}
--   local next_statenum = 2
--   seen[self.start] = 1
--   while table.getn(queue) > 0 do
--     state = table.remove(queue)
--     for char,newstates in pairs(state) do
--       if newstates.class == NFAState then newstates = {newstates} end
-- 
--       for i,newstate in ipairs(newstates) do
-- 
--         -- if we haven't seen this state before, queue it up
--         if seen[newstate] == nil then
--           table.insert(queue, newstate)
--           seen[newstate] = next_statenum
--           next_statenum = next_statenum + 1
--         end
-- 
--       str = str .. string.format('  %d -> %d [label="%s"];\n', seen[state], seen[newstate], char)
--       end
--     end
--   end
--   str = str .. string.format('  %d [label="Start"]\n', seen[self.start])
--   str = str .. string.format("  %d [peripheries=2]\n", seen[self.final])
--   str = str .. "}"
--   return str
-- end

function FA:__tostring()
  local str = "digraph untitled {\n"
  states = self:states():to_array()
  table.sort(states, function (a, b) return a.statenum < b.statenum end)
  for i,state in ipairs(states) do
    if state.class ~= FAState then print("NO") end
    local label = ""
    local peripheries = 1
    if state == self.start then label = "Begin" end
    if state == self.final or state.final then
      if label ~= "" then label = label .. "/" end
      if state.final then
        label = label .. state.final
      else
        label = label .. "Final"
      end
      peripheries = 2
    end
    str = str .. string.format('  "%s" [label="%s", peripheries=%d];\n', tostring(state), label, peripheries)
    for char,tostates in pairs(state.transitions) do
      if tostates.class == FAState then tostates = {tostates} end
      for i,tostate in ipairs(tostates) do
        local print_char
        if char == "e" then
          print_char = "ep"
        elseif char == "(" then
          print_char = "start capture"
        elseif char == ")" then
          print_char = "end capture"
        elseif type(char) == 'table' and char.class == IntSet then
          print_char = char:tostring(function (x) return string.char(x) end)
        else
          print_char = string.char(char)
        end
        str = str .. string.format('  "%s" -> "%s" [label="%s"];\n', tostring(state), tostring(tostate), print_char)
      end
    end
  end
  str = str .. "}"
  return str
end

