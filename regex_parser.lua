
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
    frag = nfa_alt(frag, newfrag)
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
  if next_char == "?" then chars:get() return nfa_alt(prim, nfa_epsilon())
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
        repeated = nfa_concat(repeated, nfa_alt(prim, nfa_epsilon()))
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
  if char == ")" or char == "|" or char == "" then return nil
  elseif char == "(" then
    local leftparen = chars:get()
    local regex = parse_regex(chars)
    local rightparen = chars:get()
    return regex
  elseif char == "[" then
    return parse_char_class(chars)
  else
    char = chars:get()
    return nfa_char(char:byte())
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
    if char:lookahead(1) == "-" then
      char:get()
      local high_char = char:get()
      table.insert(char_list, {char, high_char})
    else
      table.insert(char_list, char)
    end
  end

  local nfa
  if negated == true then
  else
    for char in set_or_array_each(char_list) do
      local sub_nfa
      if type(char) == "table" then
        sub_nfa = nfa_char(this_char[1]:byte())
        for i=this_char[1]:byte()+1, this_char[2]:byte() do
          sub_nfa = nfa_alt(sub_nfa, nfa_char(i))
        end
      else sub_nfa = nfa_char(this_char:byte())
      end

      if nfa == nil then
        nfa = sub_nfa
      else
        nfa = nfa_alt(nfa, sub_nfa)
      end
    end
  end

  return nfa
end

nfa = parse_regex(TokenStream:new("(1*01*0)*1*"))
statenum = 0
dfa = nfa_to_dfa(nfa)
-- print(nfa:dump_dot())
print(dfa:dump_dot())

