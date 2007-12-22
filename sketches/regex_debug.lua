
--dofile("sketches/pp.lua")

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

require "pp"

function fa.FA:__tostring()
  -- local oldmt = getmetatable(self)
  -- setmetatable(self, nil)
  -- print("BTW my identity is " .. tostring(self))
  -- setmetatable(self, oldmt)
  local str = "digraph untitled {\n"
  states = self:states():to_array()
  --table.sort(states, function (a, b) return a.statenum < b.statenum end)
  for i,state in ipairs(states) do
    local label = ""
    local peripheries = 1
    if state == self.start then label = "Begin" end
    if state == self.final or state.final then
      if label ~= "" then label = label .. "/" end
      if state.final then
        if type(state.final) == "table" then
          print(label)
          print(serialize(state.final:to_array()))
          label = label .. str_join(state.final:to_array(), "NEWLINE")
        else
          label = label .. state.final
        end
      else
        label = label .. "Final"
      end
      peripheries = 2
    end
    if state.decisions then
      for terminal, stack in pairs(state.decisions) do
        label = label .. "NEWLINE" .. terminal .. "->"
        if stack == Ignore then
          label = label .. "IGNORE"
        else
          for stack_member in each(stack) do
            if type(stack_member) == "table" and stack_member.class == fa.NonTerm then
              label = label .. stack_member.name
            elseif type(stack_member) == "table" and stack_member.class == Ignore then
              label = label .. "IGNORE"
            else
              label = label .. serialize(stack_member)
            end
            label = label .. ", "
          end
        end
      end
    end
    label = label:gsub("[\"\\]", "\\%1")
    label = label:gsub("NEWLINE", "\\n")
    str = str .. string.format('  "%s" [label="%s", peripheries=%d];\n', tostring(state), label, peripheries)
    for char, tostate, attributes in state:transitions() do
      local print_char
      if char == fa.e then
        print_char = "ep"
      -- elseif char == "(" then
      --   print_char = "start capture"
      -- elseif char == ")" then
      --   print_char = "end capture"
      elseif type(char) == "string" then
        print_char = char
      elseif type(char) == 'table' and char.class == IntSet then
        if char:isunbounded() then char = char:invert() end
        print_char = char:toasciistring()
      elseif type(char) == 'table' and char.class == fa.NonTerm then
        print_char = char.name
      elseif type(char) == 'table' and char.class == fa.IntFA then
        print_char = "A regex!"
      else
        print(serialize(char, 3, true))
        print_char = string.char(char)
      end
      if attributes and false then
        for k,v in pairs(attributes) do
          if k ~= "class" then
            local s = tostring(v)
            if type(v) == "table" then
              s = v.name
            end
            print_char = print_char .. string.format("NEWLINE%s: %s", k, s)
          end
        end
      end
      print_char = print_char:gsub("[\"\\]", "\\%1")
      print_char = print_char:gsub("NEWLINE", "\\n")
      str = str .. string.format('  "%s" -> "%s" [label="%s"];\n', tostring(state), tostring(tostate), print_char)
    end
  end
  str = str .. "}"
  return str
end

fa.IntFA.__tostring = fa.FA.__tostring
fa.RTN.__tostring = fa.FA.__tostring

