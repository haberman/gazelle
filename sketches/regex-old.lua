
dofile("regex_debug.lua")

NFA = {}
function NFA:new(o)
  o = o or {}
  o.start = o.start or {}
  o.final = o.final or {}
  setmetatable(o, self)
  self.__index = self
  return o
end

function nfa_concat(nfas)
  local new_nfa = NFA:new{start = nfas[1].start, final = nfas[table.getn(nfas)].final}

  for i=2,table.getn(nfas) do
    nfas[i-1].final["e"] = nfas[i].start
  end

  return new_nfa
end

function nfa_alt(nfas)
  local new_nfa = NFA:new()
  new_nfa.start["e"] = {}

  for i=1,table.getn(nfas) do
    table.insert(new_nfa.start["e"], new_nfas[i].start)
    nfas[i].final["e"] = new_nfa.final
  end

  return new_nfa
end

function nfa_kleene(nfa)
  local new_nfa = NFA:new()
  new_nfa.start["e"] = {nfa.start, new_nfa.final}
  nfa.final["e"] = {nfa.start, new_nfa.final}
  return new_nfa
end

function nfa_char(char)
  local new_nfa = NFA:new()
  new_nfa.start[char] = new_nfa.final
  return new_nfa
end

nfa = nfa_concat{nfa_kleene(nfa_char("1")), nfa_char("0")}
print(nfa:dump_dot())

