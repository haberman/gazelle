
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

function FA:dump_dot()
  local str = "digraph untitled {\n"
  states = self:states():to_array()
  table.sort(states, function (a, b) return a.statenum < b.statenum end)
  for i,state in ipairs(states) do
    if state.class ~= FAState then print("NO") end
    local label = state.statenum
    if state == self.start then label = "Begin" end
    str = str .. string.format('  "%s" [label="%s"];\n', tostring(state), label)
    for char,tostates in pairs(state.transitions) do
      --for i,tostate in pairs(tostates) do
        str = str .. string.format('  "%s" -> "%s" [label="%s"];\n', tostring(state), tostring(tostates), string.char(char))
      --end
    end
  end
  str = str .. "}"
  return str
end

