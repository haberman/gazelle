
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
    else children:add_collection(child_states) end
  end
  return children
end

function FAState:add_transition(int_set, state)
  for existing_int_set, existing_state in pairs(self.transitions) do
    if state == existing_state then
      existing_int_set:add_intset(int_set)
      return
    end
  end
  self.transitions[int_set] = state
end

function FAState:transition_for(int)
  local transitions = transitions_for(self.transitions, int):to_array()
  if #transitions == 0 then
    return nil
  else
    return transitions[1]
  end
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

