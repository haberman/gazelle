
dofile('regex.lua')

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
    for i=2, lower_bound do repeated = nfa_concat(repeated, prim) end
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
    --local regex = nfa_capture(parse_regex(chars))
    local regex = parse_regex(chars)
    local rightparen = chars:get()
    return regex
  elseif char == "[" then
    return parse_char_class(chars)
  else
    char = chars:get()
    if char == "\\" then
      char = chars:get()
      if char == "n" then char = "\n"
      elseif char == "t" then char = "\t"
      elseif char == "b" then char = "\b"
      elseif char == "f" then char = "\f"
      elseif char == "r" then char = "\r"
      end
    end
    char = nfa_char(char:byte())
    return char
  end
end

function parse_char_class(chars)
  local leftbrace = chars:get()
  local negated = false
  if chars:lookahead(1) == "^" then
    negated = true
    chars:get()
  end

  local char_list = {}
  while true do
    local char = chars:get()
    if char == "]" then break end
    if chars:lookahead(1) == "-" and chars:lookahead(2) ~= "]" then
      chars:get()
      local high_char = chars:get()
      table.insert(char_list, {char:byte(), high_char:byte()})
    else
      table.insert(char_list, char:byte())
    end
  end

  local nfa
  if negated == true then
    print("Negations not supported yet!\n")
  else
    local nfas = {}
    for char in set_or_array_each(char_list) do
      if type(char) == "table" then
        range_nfas = {}
        low_char, high_char = unpack(char)
        for i=low_char, high_char do
          table.insert(range_nfas, nfa_char(i))
        end
        table.insert(nfas, nfa_alt(range_nfas))
      else
        table.insert(nfas, nfa_char(char))
      end
    end
    nfa = nfa_alt(nfas)
  end

  return nfa
end

-- nfa = parse_regex(TokenStream:new("(1*01*0)*1*"))
-- dfa = nfa_to_dfa(nfa)
-- -- print(nfa:dump_dot())
-- print(dfa:dump_dot())

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
print(dfa:dump_dot())

