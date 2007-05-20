
FAState = {}
statenum = 1
function FAState:new(init)
  local obj = newobject(self)
  obj.transitions = init or {}
  obj.statenum = statenum
  statenum = statenum + 1
  return obj
end

function FAState:child_states()
  children = Set:new()
  for int_set, child_states in pairs(self.transitions) do
    if child_states.class == FAState then children:add(child_states)
    else children:add_array(child_states) end
  end
  return children
end

function FAState:transition_for(int)
  for int_set, child_states in pairs(self.transitions) do
    if type(int_set) == "table" and int_set:contains(int) then return child_states end
  end
  return nil
end

FA = {}
function FA:new(init)
  local obj = newobject(self)
  init = init or {}

  obj.start = init.start or FAState:new()
  obj.final = init.final or FAState:new() -- for all but Thompson NFA fragments we ignore this

  return obj
end

function FA:states()
  return breadth_first_traversal(self.start, function (s) return s:child_states() end)
end

