
-- intersection: final only if ALSO in state B
-- difference: final only if NOT ALSO in state B
-- start submatch n
-- end submatch n

dofile("fa.lua")

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

function nfa_alt2(nfa1, nfa2)
  return nfa_alt({nfa1, nfa2})
end

function nfa_alt(nfas)
  local new_nfa = FA:new()
  new_nfa.start.transitions["e"] = {}

  for i=1,#nfas do
    table.insert(new_nfa.start.transitions["e"], nfas[i].start)
    nfas[i].final.transitions["e"] = {new_nfa.final}
  end

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

function nfa_epsilon()
  return nfa_char("e")
end

