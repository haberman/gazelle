
dofile("data_structures.lua")
dofile("misc.lua")
dofile("thompson_nfa_construct.lua")

-- TokenStream
TokenStream = {}
  function TokenStream:new(string)
    local obj = newobject(self)
    obj.string = string
    return obj
  end

  function TokenStream:lookahead(amount)
    return self.string:sub(amount, amount)
  end

  function TokenStream:get()
    local char = self.string:sub(1, 1)
    self.string = self.string:sub(2, -1)
    return char
  end
-- class TokenStream


-- regex ::= frag
-- regex ::= regex "|" frag
--
-- frag  ::= term
-- frag  ::= frag term
--
-- term  ::= prim
-- term  ::= prim ?
-- term  ::= prim +
-- term  ::= prim *
-- term  ::= prim { number }
-- term  ::= prim { number , number }

-- prim  ::= char
-- prim  ::= char_class
-- prim  ::= (regex)

function parse_regex(chars)
  local frag = parse_frag(chars)
  while chars:lookahead(1) == "|" do
    local ortok = chars:get()
    local newfrag = parse_frag(chars)
    frag = nfa_alt2(frag, newfrag)
  end
  return frag
end

function parse_frag(chars)
  local term = parse_term(chars)
  while true do
    local newterm = parse_term(chars)
    if newterm == nil then return term end
    term = nfa_concat(term, newterm)
  end
end

function parse_term(chars)
  local prim = parse_prim(chars)
  if prim == nil then return nil end

  local next_char = chars:lookahead(1)
  if next_char == "?" then chars:get() return nfa_alt2(prim, nfa_epsilon())
  elseif next_char == "+" then chars:get() return nfa_rep(prim)
  elseif next_char == "*" then chars:get() return nfa_kleene(prim)
  elseif next_char == "{" then
    chars:get()
    local lower_bound = parse_number(chars)
    local repeated = prim
    for i=2, lower_bound do repeated = nfa_concat(repeated, prim:dup()) end
    next_char = chars:get()
    if next_char == "}" then return repeated
    elseif next_char == "," then
      local comma = chars:get()
      local upper_bound = parse_number(chars)
      if chars:get() ~= "}" then print("Seriously, don't do that\n") end
      for i=1, (upper_bound-lower_bound) do
        repeated = nfa_concat(repeated, nfa_alt2(prim, nfa_epsilon()))
      end
      return repeated
    else
      print("Seriously, don't do that")
    end
  else return prim
  end
end

function parse_prim(chars)
  local char = chars:lookahead(1)
  while true do
    if char == " " then chars:get(); char = chars:lookahead(1)
    else break end
  end

  if char == ")" or char == "|" or char == "" then return nil
  elseif char == "(" then
    local leftparen = chars:get()
    local regex = nfa_capture(parse_regex(chars))
    --local regex = parse_regex(chars)
    local rightparen = chars:get()
    return regex
  elseif char == "[" then
    return parse_char_class(chars)
  else
    local char, escaped = parse_char(chars)
    int_set = IntSet:new()
    if char == "." and not escaped then
      int_set:add(Range:new(0, math.huge))
    else
      int_set:add(Range:new(char:byte(), char:byte()))
    end
    char = nfa_char(int_set)
    return char
  end
end

function parse_char_class(chars)
  local leftbrace = chars:get()
  local int_set = IntSet:new()
  if chars:lookahead(1) == "^" then
    int_set.negated = true
    chars:get()
  end

  while true do
    local char, escaped = parse_char(chars)
    if char == "]" and not escaped then
      break
    end
    if chars:lookahead(1) == "-" and chars:lookahead(2) ~= "]" then
      chars:get()
      local high_char = parse_char(chars)
      int_set:add(Range:new(char:byte(), high_char:byte()))
    else
      int_set:add(Range:new(char:byte(), char:byte()))
    end
  end

  return nfa_char(int_set)
end

function parse_char(chars)
  local char = chars:get()
  local escaped = false
  if char == "\\" then
    char = chars:get()
    if char == "n" then char = "\n"
    elseif char == "t" then char = "\t"
    elseif char == "b" then char = "\b"
    elseif char == "f" then char = "\f"
    elseif char == "r" then char = "\r"
    elseif char == "s" then char = " "
    else escaped = true
    end
  end
  return char, escaped
end

function parse_number(chars)
  local num = 0
  local char = chars:lookahead(1)
  while (char:byte() >= string.byte("0")) and (char:byte() <= string.byte("9")) do
    local digit = chars:get():byte() - string.byte("0")
    num = num * 10
    num = num + digit
    char = chars:lookahead(1)
  end
  return num
end

-- nfa = parse_regex(TokenStream:new("(1*01*0)*1*"))
-- dfa = nfa_to_dfa(nfa)
-- -- print(nfa:dump_dot())
-- print(dfa:dump_dot())

dofile("nfa_to_dfa.lua")
dofile("sketches/regex_debug.lua")
dofile("minimize.lua")

statenum = 0
nfas = {}
linenum = 1
while true do
  line = io.read()
  if line == nil then break end
  nfa = parse_regex(TokenStream:new(line))
  table.insert(nfas, {nfa, "Regex" .. tostring(linenum)})
  linenum = linenum + 1
end

dfa = nfas_to_dfa(nfas)
print(dfa)
minimal_dfa = hopcroft_minimize(dfa)
print(minimal_dfa)

