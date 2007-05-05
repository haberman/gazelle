
-- intersection: final only if ALSO in state B
-- difference: final only if NOT ALSO in state B
-- start submatch n
-- end submatch n

dofile("misc.lua")
dofile("dfa.lua")

FAState = {}
statenum = 1
function FAState:new(init)
  local obj = newobject(self)
  obj.transitions = {}
  obj.statenum = statenum
  statenum = statenum + 1
  return obj
end

function FAState:child_states()
  children = Set:new()
  for char, child_states in pairs(self.transitions) do
    if child_states.class == FAState then children:add(child_states)
    else children:add_array(child_states) end
  end
  return children
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

dofile("regex_debug.lua")

function nfa_concat(nfa1, nfa2)
  if nfa1 == nil and nfa2 == nil then return nil end
  if nfa2 == nil then return nfa1 end
  if nfa1 == nil then return nfa2 end
  nfa1.final.transitions["e"] = {nfa2.start}
  return FA:new{start = nfa1.start, final = nfa2.final}
end

function nfa_capture(nfa)
  local new_nfa = FA:new()
  new_nfa.start.transitions["("], nfa.final.transitions[")"] = {nfa.start}, {new_nfa.final}
  return new_nfa
end

function nfa_alt(nfa1, nfa2)
  local new_nfa = FA:new{start = {nfa1.start, nfa2.start}}
  nfa1.final.transitions["e"], nfa2.final.transitions["e"] = {new_nfa.final}, {new_nfa.final}
  return new_nfa
end

function nfa_rep(nfa)
  local new_nfa = FA:new()
  new_nfa.start.transitions["e"] = {nfa.start}
  nfa.final.transitions["e"] = {nfa.start, new_nfa.final}
  return new_nfa
end

function nfa_kleene(nfa)
  local new_nfa = nfa_rep(nfa)
  new_nfa.start.transitions["e"] = {nfa.start, new_nfa.final}
  nfa.final.transitions["e"] = {nfa.start, new_nfa.final}
  return new_nfa
end

function nfa_char(char)
  local new_nfa = FA:new()
  new_nfa.start.transitions[char] = {new_nfa.final}
  return new_nfa
end

function parse_regex(regex)
  local nfa = nil
  local last_nfa = nil
  local stack = {}
  local stack_depth = 0
  for i=1, #regex do
    char = regex:sub(i, i)
    if char == "(" then
      nfa = nfa_concat(nfa, last_nfa)
      stack[stack_depth + 1] = nfa
      stack_depth = stack_depth + 1
      nfa, last_nfa = nil, nil
    elseif char == ")" then
      last_nfa = nfa_concat(nfa, last_nfa)
      if stack_depth < 1 then
        print("Error: unmatched right paren")
        return nil
      end
      nfa = stack[stack_depth]
      stack_depth = stack_depth - 1
    elseif char == "*" then
      last_nfa = nfa_kleene(last_nfa)
    else
      nfa = nfa_concat(nfa, last_nfa)
      last_nfa = nfa_char(char)
    end
  end
  return nfa_concat(nfa, last_nfa)
end

nfa = parse_regex("(1*01*0)*1*")
statenum = 0
dfa = nfa_to_dfa(nfa)
-- print(nfa:dump_dot())
print(dfa:dump_dot())

