--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  rtn.lua

  A parser for our grammar language that builds RTNs representing the
  input grammar.

  Copyright (c) 2007 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--
require "misc"
require "bootstrap/regex_parser"
require "fa"
--require "sketches/regex_debug"

--require "sketches/pp"
-- function fa.FA:__tostring()
--   return "<A regex!  I'm sure it's quite pretty>"
-- end

NonTerminal = {name="NonTerminal"}
function NonTerminal:new(name)
  local obj = newobject(self)
  obj.name = name
  return obj
end

--[[--------------------------------------------------------------------

grammar     -> statement*;
statement   -> nonterm "->" derivations ";" ;
derivations -> ( "e" | derivation ) +(|);
derivation  -> term+;
term        -> ( name "=" )? (regex | string | nonterm | ( "(" derivations ")" ) ) modifier ? ;
name        -> /\w+/;
modifier    -> "?" | "*" | "+" | ("*" | "+") "(" ( /[^)]*/ | string ) ")";
nonterm     -> /\w+/;
string      -> '"' /([^"]|\\")*/ '"';
string      -> "'" /([^']|\\')*/ "'";
regex       -> "/" <defer to regex parser> "/";   # TODO: deal with termination

whitespace  -> /[\r\n\s\t]+/;
ignore whitespace in grammar, statement, derivations, derivation, term

--------------------------------------------------------------------]]--

CharStream = {}
  function CharStream:new(string)
    local obj = newobject(self)
    obj.string = string
    obj.offset = 1
    return obj
  end

  function CharStream:ignore(what)
    local old_ignore = self.ignored
    self:skip_ignored()
    self.ignored = what
    self:skip_ignored()
    return old_ignore
  end

  function CharStream:skip_ignored()
    if self.ignored == "whitespace" then
      local first, last = self.string:find("^[\r\n\t ]+", self.offset)
      if last then self.offset = last+1 end
    end
  end

  function CharStream:lookahead(amount)
    self:skip_ignored()
    return self.string:sub(self.offset, self.offset+amount-1)
  end

  function CharStream:consume(str)
    self:skip_ignored()
    local actual_str = self.string:sub(self.offset, self.offset+str:len()-1)
    if actual_str ~= str then
      error(string.format("Error parsing grammar; expected %s, got %s", str, actual_str))
    end
    self.offset = self.offset + str:len()
    self:skip_ignored()
    -- print("Consumed " .. str)
    return true
  end

  function CharStream:consume_pattern(pattern)
    self:skip_ignored()
    local first, last = self.string:find("^" .. pattern, self.offset)
    if last then
      self.offset = last+1
      self:skip_ignored()
      return self.string:sub(first, last)
    else
      error(string.format("Error parsing grammar: expected to match pattern %s, but string is %s", pattern, self.string:sub(self.offset, -1)))
    end
  end

  function CharStream:match(pattern)
    self:skip_ignored()
    local first, last = self.string:find("^" .. pattern, self.offset)
    if last then
      return true
    else
      return false
    end
  end

  function CharStream:eof()
    return self.offset > self.string:len()
  end

-- class TokenStream

require "nfa_to_dfa"
require "minimize"

function parse_grammar(chars)
  chars:ignore("whitespace")
  local grammar = {}
  local attributes = {terminals={}, ignore={}, slot_counts={}}
  while not chars:eof() do
    if chars:match(" *start") then
      local start = parse_nonterm(chars)
      attributes.start = parse_nonterm(chars).name;
      chars:consume(";")
    elseif chars:match(" *allow") then
      local ignore = parse_nonterm(chars)
      local what_to_ignore = parse_nonterm(chars).name
      local in_ = parse_nonterm(chars)
      local nonterms = {parse_nonterm(chars).name}
      while chars:match(",") do
        local comma = chars:consume(",")
        table.insert(nonterms, parse_nonterm(chars).name)
      end
      for nonterm in each(nonterms) do
        attributes.ignore[nonterm] = attributes.ignore[nonterm] or Set:new()
        attributes.ignore[nonterm]:add(what_to_ignore)
      end
      chars:consume(";")
    else
      stmt = parse_statement(chars, attributes)
      if not stmt then
        break
      end
      stmt.derivations.final.final = "Final"
      grammar[stmt.nonterm.name] = hopcroft_minimize(nfa_to_dfa(stmt.derivations))
    end
  end
  return grammar, attributes
end

function parse_statement(chars, attributes)
  local old_ignore = chars:ignore("whitespace")
  local ret = {}

  ret.nonterm = parse_nonterm(chars)
  attributes.nonterm = ret.nonterm
  chars:consume("->")
  attributes.slotnum = 1
  ret.derivations = parse_derivations(chars, attributes)
  chars:consume(";")
  chars:ignore(old_ignore)
  attributes.slot_counts[ret.nonterm.name] = attributes.slotnum
  return ret
end

function parse_derivations(chars, attributes)
  local old_ignore = chars:ignore("whitespace")
  local derivations = {}

  repeat
    if chars:match(" e ") then
      table.insert(derivations, fa.RTN:new{symbol=fa.e, properties={slotnum=attributes.slotnum}})
      attributes.slotnum = attributes.slotnum + 1
    else
      table.insert(derivations, parse_derivation(chars, attributes))
    end
  until chars:lookahead(1) ~= "|" or not chars:consume("|")

  chars:ignore(old_ignore)
  return nfa_construct.alt(derivations)
end

function parse_derivation(chars, attributes)
  local old_ignore = chars:ignore("whitespace")
  local ret = parse_term(chars, attributes)
  while chars:lookahead(1) ~= "|" and chars:lookahead(1) ~= ";" and chars:lookahead(1) ~= ")" do
    ret = nfa_construct.concat(ret, parse_term(chars, attributes))
  end
  chars:ignore(old_ignore)
  return ret
end

function parse_term(chars, attributes)
  local old_ignore = chars:ignore("whitespace")
  local name
  local ret
  if chars:match(" *[%w_]+ *=") then
    name = parse_name(chars)
    chars:consume("=")
  end

  local symbol
  if chars:lookahead(1) == "/" then
    name = name or attributes.nonterm.name
    attributes.terminals[name] = parse_regex(chars)
    ret = fa.RTN:new{symbol=name, properties={name=name, slotnum=attributes.slotnum}}
    attributes.slotnum = attributes.slotnum + 1
  elseif chars:lookahead(1) == "'" or chars:lookahead(1) == '"' then
    local string = parse_string(chars)
    attributes.terminals[string] = string
    name = name or string
    ret = fa.RTN:new{symbol=string, properties={name=name, slotnum=attributes.slotnum}}
    attributes.slotnum = attributes.slotnum + 1
  elseif chars:lookahead(1) == "(" then
    if name then error("You cannot name a group") end
    chars:consume("(")
    ret = parse_derivations(chars, attributes)
    chars:consume(")")
  else
    local nonterm = parse_nonterm(chars)
    name = name or nonterm.name
    ret = fa.RTN:new{symbol=nonterm, properties={name=name, slotnum=attributes.slotnum}}
    attributes.slotnum = attributes.slotnum + 1
  end

  local one_ahead = chars:lookahead(1)
  if one_ahead == "?" or one_ahead == "*" or one_ahead == "+" then
    local modifier, sep = parse_modifier(chars, attributes)
    -- foo +(bar) == foo (bar foo)*
    -- foo *(bar) == (foo (bar foo)*)?
    if sep then
      if modifier == "?" then error("Question mark with separator makes no sense") end
      ret = nfa_construct.concat(ret:dup(), nfa_construct.kleene(nfa_construct.concat(sep, ret:dup())))
      if modifier == "*" then
        ret = nfa_construct.alt2(fa.RTN:new{symbol=fa.e}, ret)
      end
    else
      if modifier == "?" then
        ret = nfa_construct.alt2(fa.RTN:new{symbol=fa.e}, ret)
      elseif modifier == "*" then
        ret = nfa_construct.kleene(ret)
      elseif modifier == "+" then
        ret = nfa_construct.rep(ret)
      end
    end
  end

  chars:ignore(old_ignore)
  return ret
end

function parse_name(chars)
  local old_ignore = chars:ignore()
  local ret = chars:consume_pattern("[%w_]+")
  chars:ignore(old_ignore)
  return ret
end

function parse_modifier(chars, attributes)
  local old_ignore = chars:ignore()
  local modifier, str
  modifier = chars:consume_pattern("[?*+]")
  if chars:lookahead(1) == "(" then
    chars:consume("(")
    local sep_string
    if chars:lookahead(1) == "'" or chars:lookahead(1) == '"' then
      sep_string = parse_string()
    else
      sep_string = chars:consume_pattern("[^)]*")
    end
    str = fa.RTN:new{symbol=sep_string, properties={slotnum=attributes.slotnum, name=sep_string}}
    attributes.terminals[sep_string] = sep_string
    attributes.slotnum = attributes.slotnum + 1
    chars:consume(")")
  end
  chars:ignore(old_ignore)
  return modifier, str
end

function parse_nonterm(chars)
  local old_ignore = chars:ignore()
  local ret = fa.NonTerm:new(chars:consume_pattern("[%w_]+"))
  chars:ignore(old_ignore)
  return ret
end

function parse_string(chars)
  local old_ignore = chars:ignore()
  local str = ""
  if chars:lookahead(1) == "'" then
    chars:consume("'")
    while chars:lookahead(1) ~= "'" do
      if chars:lookahead(1) == "\\" then
        chars:consume("\\")
        str = str .. chars:consume_pattern(".") -- TODO: other backslash sequences
      else
        str = str .. chars:consume_pattern(".")
      end
    end
    chars:consume("'")
  else
    chars:consume('"')
    while chars:lookahead(1) ~= '"' do
      if chars:lookahead(1) == "\\" then
        chars:consume("\\")
        str = str .. chars:consume_pattern(".") -- TODO: other backslash sequences
      else
        str = str .. chars:consume_pattern(".")
      end
    end
    chars:consume('"')
  end
  chars:ignore(old_ignore)
  return str
end

function parse_regex(chars)
  local old_ignore = chars:ignore()
  chars:consume("/")
  local regex = ""
  while chars:lookahead(1) ~= "/" do
    if chars:lookahead(1) == "\\" then
      regex = regex .. chars:consume_pattern("..")
    else
      regex = regex .. chars:consume_pattern(".")
    end
  end
  local regex = regex_parser.parse_regex(regex_parser.TokenStream:new(regex))
  chars:consume("/")
  chars:ignore(old_ignore)
  return regex
end

-- vim:et:sts=2:sw=2
