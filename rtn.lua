
require "misc"
require "regex_parser"

require "sketches/pp"
function FA:__tostring()
  return "<A regex!  I'm sure it's quite pretty>"
end

-- RTN = {name="RTN"}
-- function RTN:new(init)
--   local obj = newobject(self)
--   return obj
-- end
-- 
-- RTNState = {name="RTNState"}
-- function RTNState:new(init)
--   local obj = newobject(self)
--   obj.transitions = {}
--   return obj
-- end
-- 
-- function RTNState:add_transition(on, dest_state)
--   table.insert(self.transitions, {on, dest_state})
-- end
-- 
-- RTNEpsilon = {name="RTNEpsilon"}
-- function RTNState:new()
--   local obj = newobject(self)
--   return obj
-- end
-- 
-- RTNString = {name="RTNString"}
-- function RTNState:new(str)
--   local obj = newobject(self)
--   obj.string = str
--   return obj
-- end
-- 
-- RTNDFA = {name="RTNDFA"}
-- function RTNState:new(dfa)
--   local obj = newobject(self)
--   obj.dfa = dfa
--   return obj
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

function parse_grammar(chars)
  chars:ignore("whitespace")
  local grammar = {}
  while not chars:eof() do
    stmt = parse_statement(chars)
    if not stmt then
      break
    end
    grammar[stmt.nonterm] = grammar[stmt.nonterm] or {}
    for derivation in each(stmt.derivations) do
      table.insert(grammar[stmt.nonterm], derivation)
    end
  end
  return grammar
end

function parse_statement(chars)
  local old_ignore = chars:ignore("whitespace")
  local ret = {}

  ret.nonterm = parse_nonterm(chars)
  print(ret.nonterm)
  chars:consume("->")
  ret.derivations = parse_derivations(chars)
  chars:consume(";")
  chars:ignore(old_ignore)
  return ret
end

function parse_derivations(chars)
  local old_ignore = chars:ignore("whitespace")
  local ret = {}
  if chars:lookahead(1) == "e" then
    ret = {"e"}
  else
    ret = {parse_derivation(chars)}
  end

  while chars:lookahead(1) == "|" do
    chars:consume("|")
    if chars:lookahead(1) == "e" then
      table.insert(ret, "e")
    else
      table.insert(ret, parse_derivation(chars))
    end
  end
  chars:ignore(old_ignore)
  return ret
end

function parse_derivation(chars)
  local old_ignore = chars:ignore("whitespace")
  local ret = {parse_term(chars)}
  while chars:lookahead(1) ~= "|" and chars:lookahead(1) ~= ";" and chars:lookahead(1) ~= ")" do
    table.insert(ret, parse_term(chars))

  end
  chars:ignore(old_ignore)
  return ret
end

function parse_term(chars)
  local old_ignore = chars:ignore("whitespace")
  local ret = {}
  if chars:match("\s*\w+\s*=") then
    ret.name = parse_name(chars)
    chars:consume("=")
  end

  if chars:lookahead(1) == "/" then
    ret.regex = parse_regex(chars)
  elseif chars:lookahead(1) == "'" or chars:lookahead(1) == '"' then
    ret.string = parse_string(chars)
  elseif chars:lookahead(1) == "(" then
    chars:consume("(")
    ret.derivation = parse_derivations(chars)
    chars:consume(")")
  else
    ret.nonterm = parse_nonterm(chars)
  end

  local one_ahead = chars:lookahead(1)
  if one_ahead == "?" or one_ahead == "*" or one_ahead == "+" then
    ret.modifier = parse_modifier(chars)
  end
  chars:ignore(old_ignore)
  return ret
end

function parse_name(chars)
  local old_ignore = chars:ignore()
  local ret = chars:consume_pattern("%w+")
  chars:ignore(old_ignore)
  return ret
end

function parse_modifier(chars)
  local old_ignore = chars:ignore()
  local ret = {}
  ret.modifier = chars:consume_pattern("[?*+]")
  if chars:lookahead(1) == "(" then
    chars:consume("(")
    if chars:lookahead(1) == "'" or chars:lookahead(1) == '"' then
      ret.string = parse_string()
    else
      ret.sep = chars:consume_pattern("[^)]*")
    end
    chars:consume(")")
  end
  chars:ignore(old_ignore)
  return ret
end

function parse_nonterm(chars)
  local old_ignore = chars:ignore()
  local ret = NonTerminal:new(chars:consume_pattern("[%w_]+"))
  chars:ignore(old_ignore)
  return ret
end

function parse_string(chars)
  local old_ignore = chars:ignore()
  local ret = {}
  ret.str = ""
  if chars:lookahead(1) == "'" then
    chars:consume("'")
    while chars:lookahead(1) ~= "'" do
      if chars:lookahead(1) == "\\" then
        chars:consume("\\")
        ret.str = ret.str .. chars:consume_pattern(".") -- TODO: other backslash sequences
      else
        ret.str = ret.str .. chars:consume_pattern(".")
      end
    end
    chars:consume("'")
  else
    chars:consume('"')
    while chars:lookahead(1) ~= '"' do
      if chars:lookahead(1) == "\\" then
        chars:consume("\\")
        ret.str = ret.str .. chars:consume_pattern(".") -- TODO: other backslash sequences
      else
        ret.str = ret.str .. chars:consume_pattern(".")
      end
    end
    chars:consume('"')
  end
  chars:ignore(old_ignore)
  return ret
end

function parse_regex(chars)
  local old_ignore = chars:ignore()
  local ret = {}
  chars:consume("/")
  local regex = ""
  while chars:lookahead(1) ~= "/" do
    if chars:lookahead(1) == "\\" then
      regex = regex .. chars:consume_pattern("..")
    else
      regex = regex .. chars:consume_pattern(".")
    end
  end
  ret.regex = regex_parser.parse_regex(regex_parser.TokenStream:new(regex))
  chars:consume("/")
  chars:ignore(old_ignore)
  return ret
end

grammar_str = ""
while true do
  local str = io.read()
  if str == nil then break end
  grammar_str = grammar_str .. str
end

grammar = parse_grammar(CharStream:new(grammar_str))

print(serialize(grammar, 15, true))
require "sketches/regex_debug"




