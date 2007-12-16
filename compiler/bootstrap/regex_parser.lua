--[[--------------------------------------------------------------------

  regex_parser.lua

  A hand-written recursive descent parser to parse regular expressions.
  Hopefully this could eventually be implemented using the engine itself,
  but even then you need a way to bootstrap.

  Copyright (c) 2007 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

require "data_structures"
require "misc"
require "nfa_construct"

module("regex_parser", package.seeall)

-- class TokenStream
-- A simple convenience class for reading characters one at a time and
-- doing simple lookahead.  It is not especially efficient.
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
    if char == "" then
      error("Premature end of regex!")
    end
    self.string = self.string:sub(2, -1)
    return char
  end
-- class TokenStream

--[[--------------------------------------------------------------------

  The grammar we are working from is:

  regex -> frag *(|);
  frag  -> term *;
  term  -> prim modifier ?
  modifier -> "?" | "+" | "*" | "{" number "}" | "{" number "," number "}";
  prim  -> char | char_class | "(" regex ")";
  char  -> /\\./ | /[^\\]/;
  char_class -> "[" ( class_char "-" class_char | class_char )* "]";
  class_char -> /\\./ | /[^\]\\]/;
  number -> /\d+/;

  whitespace -> /[\r\n\t\s]+/;
  ignore whitespace in regex, frag, term, prim;

--------------------------------------------------------------------]]--

function parse_regex(chars)
  local regex_str = chars.string
  local frags = {parse_frag(chars)}
  while chars:lookahead(1) == "|" do
    local ortok = chars:get()
    table.insert(frags, parse_frag(chars))
  end
  local nfa = nfa_construct.alt(frags)
  nfa.properties.string = regex_str
  return nfa
end

function parse_frag(chars)
  local term = parse_term(chars)
  while true do
    local newterm = parse_term(chars)
    if newterm == nil then return term end
    term = nfa_construct.concat(term, newterm)
  end
end

function parse_term(chars)
  local prim = parse_prim(chars)
  if prim == nil then return nil end

  local next_char = chars:lookahead(1)
  if next_char == "?" then chars:get() return nfa_construct.alt2(prim, fa.IntFA:new{symbol=fa.e})
  elseif next_char == "+" then chars:get() return nfa_construct.rep(prim)
  elseif next_char == "*" then chars:get() return nfa_construct.kleene(prim)
  elseif next_char == "{" then
    chars:get()
    local lower_bound = parse_number(chars)
    local repeated = prim:dup()
    for i=2, lower_bound do repeated = nfa_construct.concat(repeated, prim:dup()) end
    next_char = chars:get()
    if next_char == "}" then return repeated
    elseif next_char == "," then
      local comma = chars:get()
      local upper_bound = parse_number(chars)
      if chars:get() ~= "}" then print("Seriously, don't do that\n") end
      for i=1, (upper_bound-lower_bound) do
        repeated = nfa_construct.concat(repeated, nfa_construct.alt2(prim:dup(), nfa_construct.epsilon()))
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
    --local regex = nfa_construct.capture(parse_regex(chars))
    local regex = parse_regex(chars)
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
    char = fa.IntFA:new{symbol=int_set}
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

  return fa.IntFA:new{symbol=int_set}
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

-- vim:et:sts=2:sw=2
