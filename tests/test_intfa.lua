--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  tests/test_intfa.lua

  Routines that test the generation of IntFAs.

--------------------------------------------------------------------]]--

require "luaunit"
require "bootstrap/rtn"
require "grammar"
require "ll"

function assert_intfas(grammar_str, ...)
  local grammar = Grammar:new()
  grammar:parse_source_string(grammar_str)
  grammar:process()
  grammar:minimize_rtns()
  grammar:compute_lookahead()
  grammar:generate_intfas()

  local intfa_strings = {...}
  if #intfa_strings ~= grammar.master_intfas:count() then
    error(string.format("Expected to get %d IntFAs but got %d instead",
                        #intfa_strings, #grammar.master_intfas))
  end

  for i, intfa_string in pairs(intfa_strings) do
    local expected_intfa = parse_intfa(intfa_string)
    local actual_intfa = grammar.master_intfas:element_at(i)
    if not fa_isequal(expected_intfa, actual_intfa) then
      local bad = io.open("bad.dot", "w")
      bad:write("digraph untitled {\n")
      bad:write(actual_intfa:to_dot("  "))
      bad:write("}")
      bad:close()

      local good = io.open("good.dot", "w")
      good:write("digraph untitled {\n")
      good:write(expected_intfa:to_dot("  "))
      good:write("}")
      good:close()

      os.execute("dot -Tpng -o good.png good.dot")
      os.execute("dot -Tpng -o bad.png bad.dot")

      error("GLAs were not equal: expected and actual are " ..
            "in good.png and bad.png, respectively")
    end
  end
end

function parse_intfa(str)
  local stream = CharStream:new(str)
  stream:ignore("whitespace")
  local intfa = fa.RTN:new()
  local states = {[1]=intfa.start}
  while not stream:eof() do
    local statenum = tonumber(stream:consume_pattern("%d+"))
    local state = states[statenum]
    if not state then
      error(string.format("IntFA refers to state %d before it is used as a target",
            statenum))
    end
    while stream:lookahead(1) ~= ";" do
      stream:consume("-")
      local term = stream:consume_pattern("%w"):byte()
      stream:consume("->")
      local dest_state_num = tonumber(stream:consume_pattern("%d+"))
      states[dest_state_num] = states[dest_state_num] or fa.IntFAState:new()
      local dest_state = states[dest_state_num]
      state:add_transition(term, dest_state)
      if stream:lookahead(1) == "(" then
        stream:consume("(")
        dest_state.final = stream:consume_pattern("%w+")
        stream:consume(")")
      end
      state = dest_state
    end
    stream:consume(";")
  end

  return intfa
end

TestIntFA = {}
function TestIntFA:test1()
  assert_intfas(
  [[
    s -> "X" "Y";
  ]],
  [[
    1 -X-> 2(X);
    1 -Y-> 3(Y);
  ]]
  )
end

function TestIntFA:test2()
  assert_intfas(
  [[
    s -> "X" | a;
    a -> "Y";
  ]],
  [[
    1 -X-> 2(X);
    1 -Y-> 3(Y);
  ]]
  )
end
