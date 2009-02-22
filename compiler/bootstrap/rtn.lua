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
define_class("CharStream")
  function CharStream:initialize(string)
    self.string = string
    self.offset = 1
    self.ignored = nil
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

  function CharStream:get_offset()
    -- Inefficient, but this is only until we are self-hosting.
    local lineno = 1
    for nl in self.string:sub(0, self.offset):gmatch("[\n\r]+") do lineno = lineno + 1 end
    local first, last = self.string:sub(0, self.offset):find(".*[\n\r]")
    local colno = self.offset - (last or 0)
    return TextOffset:new(lineno, colno, self.offset)
  end

  function CharStream:consume(str)
    self:skip_ignored()
    local actual_str = self.string:sub(self.offset, self.offset+str:len()-1)
    if actual_str ~= str then
      local offset = self:get_offset()
      error(string.format("Error parsing grammar %s:\nat line %s, column %s " ..
                          "(expected '%s', got '%s')",
                          input_filename, offset.line, offset.column, str, actual_str))
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
define_class("RTNParser")
function RTNParser:initialize()
  self.grammar = nil
  self.chars = nil
  self.slotnum = nil
  self.current_rule_name = nil
end

function RTNParser:parse(chars, grammar)
  self.chars = chars
  self.grammar = grammar
  self:parse_grammar()
  return grammar
end

function RTNParser:get_next_slotnum()
  local ret = self.slotnum
  self.slotnum = self.slotnum + 1
  return ret
end

function RTNParser:parse_grammar()
  local chars = self.chars
  chars:ignore("whitespace")
  while not chars:eof() do
    if chars:match(" *@start") then
      chars:consume_pattern(" *@start")
      self.grammar.start = self:parse_ident()
      chars:consume(";")
    elseif chars:match(" *@allow") then
      chars:consume_pattern(" *@allow")
      local what_to_allow = self:parse_ident()
      local start_ident = self:parse_ident()
      chars:consume_pattern("%.%.%.")
      local end_idents = Set:new()
      end_idents:add(self:parse_ident())
      while chars:match(" *,") do
        chars:consume(",")
        end_idents:add(self:parse_ident())
      end
      chars:consume(";")
      self.grammar:add_allow(what_to_allow, start_ident, end_idents)
    else
      local before_offset = chars.offset
      local offset = chars:get_offset()
      local stmt = self:parse_statement()
      if not stmt then
        break
      elseif stmt.nonterm then
        stmt.derivations.final.final = "Final"
        local rule_text = chars.string:sub(before_offset, chars.offset-1)
        self.grammar:add_nonterm(stmt.nonterm, stmt.derivations, stmt.slot_count, rule_text, offset)
      elseif stmt.term then
        self.grammar:add_terminal(stmt.term, stmt.regex, offset)
      end
    end
  end
end

function RTNParser:parse_statement()
  local old_ignore = self.chars:ignore("whitespace")
  local ret = {}

  local ident = self:parse_ident()

  if self.chars:match("->") then
    self.current_rule_name = ident
    -- Need to register the rule here, so that we catch conflicting references
    -- *within* the rule, and so that ordering of symbols is right.
    self.grammar:get_object(ident, {GrammarObj.RULE})
    ret.nonterm = ident
    self.chars:consume("->")
    self.slotnum = 1
    ret.derivations = self:parse_derivations()
    ret.slot_count = self.slotnum - 1
  else
    ret.term = ident
    self.chars:consume(":")
    ret.regex = self:parse_regex()
  end

  self.chars:consume(";")
  self.chars:ignore(old_ignore)
  return ret
end

function RTNParser:parse_derivations()
  local old_ignore = self.chars:ignore("whitespace")
  local derivations = {}

  repeat
    local derivation = self:parse_derivation()

    -- Any prioritized derivations we parse together as a group, then build
    -- an NFA of *prioritized* alternation.
    if self.chars:lookahead(1) == "/" then
      self.chars:consume("/")
      local prioritized_derivations = {derivation}
      repeat
        local prioritized_derivation = self:parse_derivation()
        table.insert(prioritized_derivations, prioritized_derivation)
      until self.chars:lookahead(1) ~= "/" or not self.chars:consume("/")
      derivation = nfa_construct.alt(prioritized_derivations, true)
    end

    table.insert(derivations, derivation)
  until self.chars:lookahead(1) ~= "|" or not self.chars:consume("|")

  self.chars:ignore(old_ignore)
  return nfa_construct.alt(derivations)
end

function RTNParser:parse_derivation()
  local old_ignore = self.chars:ignore("whitespace")
  local ret = self:parse_term()
  while self.chars:lookahead(1) ~= "|" and self.chars:lookahead(1) ~= "/" and
        self.chars:lookahead(1) ~= ";" and self.chars:lookahead(1) ~= ")" do
    ret = nfa_construct.concat(ret, self:parse_term())
  end
  self.chars:ignore(old_ignore)
  return ret
end

function RTNParser:parse_term()
  local old_ignore = self.chars:ignore("whitespace")
  local name
  local ret
  local offset = self.chars:get_offset()
  if self.chars:match(" *%.[%w_]+ *=") then
    name = self:parse_name()
    self.chars:consume("=")
  end

  local symbol
  if self.chars:lookahead(1) == "/" and name then
    local intfa, text = self:parse_regex()
    local obj = self.grammar:add_terminal(name, intfa, text, offset)
    ret = fa.RTN:new{
      symbol=obj,
      properties={name=name, slotnum=self:get_next_slotnum()}
    }
  elseif self.chars:lookahead(1) == "'" or self.chars:lookahead(1) == '"' then
    local string = self:parse_string()
    name = name or string
    local obj = self.grammar:add_implicit_terminal(name, string, offset)
    ret = fa.RTN:new{
      symbol=obj,
      properties={name=name, slotnum=self:get_next_slotnum()}
    }
  elseif self.chars:lookahead(1) == "(" then
    if name then error("You cannot name a group") end
    self.chars:consume("(")
    ret = self:parse_derivations()
    self.chars:consume(")")
  else
    local ident = self:parse_ident()
    name = name or ident
    ret = fa.RTN:new{
        symbol=self.grammar:get_object(ident, {GrammarObj.RULE, GrammarObj.TERMINAL}),
        properties={name=ident, slotnum=self:get_next_slotnum()}
    }
  end

  local one_ahead = self.chars:lookahead(1)
  if one_ahead == "?" or one_ahead == "*" or one_ahead == "+" then
    local modifier, sep, favor_repeat = self:parse_modifier()
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

  self.chars:ignore(old_ignore)
  return ret
end

function RTNParser:parse_name()
  local old_ignore = self.chars:ignore()
  self.chars:consume(".")
  local ret = self.chars:consume_pattern("[%w_]+")
  self.chars:ignore(old_ignore)
  return ret
end

function RTNParser:parse_modifier()
  local old_ignore = self.chars:ignore()
  local modifier, str, prefer_repeat
  modifier = self.chars:consume_pattern("[?*+]")
  if self.chars:lookahead(1) == "(" then
    self.chars:consume("(")
    local offset = self.chars:get_offset()
    local sep_string
    if self.chars:lookahead(1) == "'" or self.chars:lookahead(1) == '"' then
      sep_string = self:parse_string()
    else
      sep_string = self.chars:consume_pattern("[^)]*")
    end
    local obj = self.grammar:add_implicit_terminal(sep_string, sep_string, offset)
    str = fa.RTN:new{symbol=obj, properties={slotnum=self:get_next_slotnum(), name=sep_string}}
    self.chars:consume(")")
  end
  if self.chars:lookahead(1) == "+" or self.chars:lookahead(1) == "-" then
    local prefer_repeat_ch = self.chars:consume_pattern("[+-]")
    if prefer_repeat_ch == "+" then
      prefer_repeat = true
    else
      prefer_repeat = false
    end
  end
  self.chars:ignore(old_ignore)
  return modifier, str, prefer_repeat
end

function RTNParser:parse_ident()
  local old_ignore = self.chars:ignore()
  local ret = self.chars:consume_pattern("[%w_]+")
  self.chars:ignore(old_ignore)
  return ret
end

function RTNParser:parse_string()
  local old_ignore = self.chars:ignore()
  local str = ""
  if self.chars:lookahead(1) == "'" then
    self.chars:consume("'")
    while self.chars:lookahead(1) ~= "'" do
      if self.chars:lookahead(1) == "\\" then
        self.chars:consume("\\")
        str = str .. self.chars:consume_pattern(".") -- TODO: other backslash sequences
      else
        str = str .. self.chars:consume_pattern(".")
      end
    end
    self.chars:consume("'")
  else
    self.chars:consume('"')
    while self.chars:lookahead(1) ~= '"' do
      if self.chars:lookahead(1) == "\\" then
        self.chars:consume("\\")
        str = str .. self.chars:consume_pattern(".") -- TODO: other backslash sequences
      else
        str = str .. self.chars:consume_pattern(".")
      end
    end
    self.chars:consume('"')
  end
  self.chars:ignore(old_ignore)
  return str
end

function RTNParser:parse_regex()
  local old_ignore = self.chars:ignore()
  self.chars:consume("/")
  local regex_text = ""
  while self.chars:lookahead(1) ~= "/" do
    if self.chars:lookahead(1) == "\\" then
      regex_text = regex_text .. self.chars:consume_pattern("..")
    else
      regex_text = regex_text .. self.chars:consume_pattern(".")
    end
  end
  local regex = regex_parser.parse_regex(regex_parser.TokenStream:new(regex_text))
  regex.regex_text = regex_text
  self.chars:consume("/")
  self.chars:ignore(old_ignore)
  return regex, regex_text
end

-- vim:et:sts=2:sw=2
