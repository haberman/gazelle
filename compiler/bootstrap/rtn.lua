--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  rtn.lua

  A parser for our grammar language that builds RTNs representing the
  input grammar.

  Copyright (c) 2007-2008 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

require "misc"
require "fa"
require "grammar"

require "bootstrap/regex_parser"

-- CharStream: a cheesy sort-of lexer-like object for the RTN parser
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
      local found = true
      while found do
        found = false
        -- skip whitespace
        local first, last = self.string:find("^[\r\n\t ]+", self.offset)
        if last then
          found = true
          self.offset = last+1
        end
        -- skip comments
        first, last = self.string:find("^//[^\n]*\n", self.offset)
        if last then
          found = true
          self.offset = last+1
        end
        first, last = self.string:find("^/%*.*%*/", self.offset)
        if last then
          found = true
          self.offset = last+1
        end
      end
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
      local lineno = 1
      for nl in self.string:sub(0, self.offset):gmatch("[\n\r]") do lineno = lineno + 1 end
      local first, last = self.string:sub(0, self.offset):find(".*[\n\r]")
      local colno = self.offset - (last or 0)
      error(string.format("Error parsing grammar %s:\nat line %s, column %s expected '%s', got '%s'", input_filename, lineno, colno, str, actual_str))
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

-- Parse the grammar file given in +chars+ and return a Grammar object.
function parse_grammar(chars)
  chars:ignore("whitespace")
  local grammar = Grammar:new()
  local attributes = {ignore={}, slot_counts={}, regex_text={}, grammar=grammar}
  while not chars:eof() do
    if chars:match(" *@start") then
      chars:consume_pattern(" *@start")
      grammar.start = parse_nonterm(chars).name;
      chars:consume(";")
    elseif chars:match(" *@allow") then
      chars:consume_pattern(" *@allow")
      local what_to_allow = parse_nonterm(chars);
      local start_nonterm = parse_nonterm(chars).name;
      chars:consume_pattern("%.%.%.")
      local end_nonterms = Set:new()
      end_nonterms:add(parse_nonterm(chars).name)
      while chars:match(" *,") do
        chars:consume(",")
        end_nonterms:add(parse_nonterm(chars).name)
      end
      chars:consume(";")
      grammar:add_allow(what_to_allow, start_nonterm, end_nonterms)
    else
      local before_offset = chars.offset
      local stmt = parse_statement(chars, attributes)
      if not stmt then
        break
      elseif stmt.nonterm then
        stmt.derivations.final.final = "Final"
        local rule_text = chars.string:sub(before_offset, chars.offset-1)
        grammar:add_nonterm(stmt.nonterm.name, stmt.derivations, stmt.slot_count, rule_text)
      elseif stmt.term then
        grammar:add_terminal(stmt.term, stmt.regex)
      end
    end
  end

  grammar.attributes = attributes

  -- start symbol defaults to the first symbol
  if not grammar.start then
    grammar.start = grammar.rtns:get_key_at_offset(1)
  end

  return grammar
end

function parse_statement(chars, attributes)
  local old_ignore = chars:ignore("whitespace")
  local ret = {}

  local ident = parse_nonterm(chars)

  if chars:match("->") then
    attributes.nonterm = ident
    ret.nonterm = ident
    chars:consume("->")
    attributes.slotnum = 1
    ret.derivations = parse_derivations(chars, attributes)
    ret.slot_count = attributes.slotnum - 1
  else
    ret.term = ident.name
    chars:consume(":")
    ret.regex = parse_regex(chars)
  end

  chars:consume(";")
  chars:ignore(old_ignore)
  return ret
end

function parse_derivations(chars, attributes)
  local old_ignore = chars:ignore("whitespace")
  local derivations = {}

  repeat
    local derivation = parse_derivation(chars, attributes)

    -- Any prioritized derivations we parse together as a group, then build
    -- an NFA of *prioritized* alternation.
    if chars:lookahead(1) == "/" then
      chars:consume("/")
      local prioritized_derivations = {derivation}
      repeat
        local prioritized_derivation = parse_derivation(chars, attributes)
        table.insert(prioritized_derivations, prioritized_derivation)
      until chars:lookahead(1) ~= "/" or not chars:consume("/")
      derivation = nfa_construct.alt(prioritized_derivations, true)
    end

    table.insert(derivations, derivation)
  until chars:lookahead(1) ~= "|" or not chars:consume("|")

  chars:ignore(old_ignore)
  return nfa_construct.alt(derivations)
end

function parse_derivation(chars, attributes)
  local old_ignore = chars:ignore("whitespace")
  local ret = parse_term(chars, attributes)
  while chars:lookahead(1) ~= "|" and chars:lookahead(1) ~= "/" and
        chars:lookahead(1) ~= ";" and chars:lookahead(1) ~= ")" do
    ret = nfa_construct.concat(ret, parse_term(chars, attributes))
  end
  chars:ignore(old_ignore)
  return ret
end

function parse_term(chars, attributes)
  local old_ignore = chars:ignore("whitespace")
  local name
  local ret
  if chars:match(" *%.[%w_]+ *=") then
    name = parse_name(chars)
    chars:consume("=")
  end

  local symbol
  if chars:lookahead(1) == "/" and name then
    name = name or attributes.nonterm.name
    intfa, text = parse_regex(chars)
    attributes.grammar:add_terminal(name, intfa, text)
    ret = fa.RTN:new{symbol=name, properties={name=name, slotnum=attributes.slotnum}}
    attributes.slotnum = attributes.slotnum + 1
  elseif chars:lookahead(1) == "'" or chars:lookahead(1) == '"' then
    local string = parse_string(chars)
    attributes.grammar:add_terminal(string, string)
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
    if attributes.grammar.terminals[nonterm.name] then
      ret = fa.RTN:new{symbol=nonterm.name, properties={name=nonterm.name, slotnum=attributes.slotnum}}
    else
      ret = fa.RTN:new{symbol=nonterm, properties={name=name, slotnum=attributes.slotnum}}
    end
    attributes.slotnum = attributes.slotnum + 1
  end

  local one_ahead = chars:lookahead(1)
  if one_ahead == "?" or one_ahead == "*" or one_ahead == "+" then
    local modifier, sep, favor_repeat = parse_modifier(chars, attributes)
    -- foo +(bar) == foo (bar foo)*
    -- foo *(bar) == (foo (bar foo)*)?
    if sep then
      if modifier == "?" then error("Question mark with separator makes no sense") end
      ret = nfa_construct.concat(ret:dup(), nfa_construct.kleene(nfa_construct.concat(sep, ret:dup()), favor_repeat))
      if modifier == "*" then
        -- TODO: should the priority for the question mark use the same priority
        -- class as the priority for the repetition?  Are the two even distinguishable
        -- (ie. is there a test whose output depends on this)?
        if favor_repeat then
          ret = nfa_construct.alt2(ret, fa.RTN:new{symbol=fa.e}, true)
        elseif favor_repeat == false then
          ret = nfa_construct.alt2(fa.RTN:new{symbol=fa.e}, ret, true)
        else
          ret = nfa_construct.alt2(fa.RTN:new{symbol=fa.e}, ret)
        end
      end
    else
      if modifier == "?" then
        if favor_repeat then
          ret = nfa_construct.alt2(ret, fa.RTN:new{symbol=fa.e}, true)
        elseif favor_repeat == false then
          ret = nfa_construct.alt2(fa.RTN:new{symbol=fa.e}, ret, true)
        else
          ret = nfa_construct.alt2(fa.RTN:new{symbol=fa.e}, ret)
        end
      elseif modifier == "*" then
        ret = nfa_construct.kleene(ret, favor_repeat)
      elseif modifier == "+" then
        ret = nfa_construct.rep(ret, favor_repeat)
      end
    end
  end

  chars:ignore(old_ignore)
  return ret
end

function parse_name(chars)
  local old_ignore = chars:ignore()
  chars:consume(".")
  local ret = chars:consume_pattern("[%w_]+")
  chars:ignore(old_ignore)
  return ret
end

function parse_modifier(chars, attributes)
  local old_ignore = chars:ignore()
  local modifier, str, prefer_repeat
  modifier = chars:consume_pattern("[?*+]")
  if chars:lookahead(1) == "(" then
    chars:consume("(")
    local sep_string
    if chars:lookahead(1) == "'" or chars:lookahead(1) == '"' then
      sep_string = parse_string(chars)
    else
      sep_string = chars:consume_pattern("[^)]*")
    end
    str = fa.RTN:new{symbol=sep_string, properties={slotnum=attributes.slotnum, name=sep_string}}
    attributes.grammar:add_terminal(sep_string, sep_string)
    attributes.slotnum = attributes.slotnum + 1
    chars:consume(")")
  end
  if chars:lookahead(1) == "+" or chars:lookahead(1) == "-" then
    local prefer_repeat_ch = chars:consume_pattern("[+-]")
    if prefer_repeat_ch == "+" then
      prefer_repeat = true
    else
      prefer_repeat = false
    end
  end
  chars:ignore(old_ignore)
  return modifier, str, prefer_repeat
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
  local regex_text = ""
  while chars:lookahead(1) ~= "/" do
    if chars:lookahead(1) == "\\" then
      regex_text = regex_text .. chars:consume_pattern("..")
    else
      regex_text = regex_text .. chars:consume_pattern(".")
    end
  end
  local regex = regex_parser.parse_regex(regex_parser.TokenStream:new(regex_text))
  chars:consume("/")
  chars:ignore(old_ignore)
  return regex, regex_text
end

-- vim:et:sts=2:sw=2
