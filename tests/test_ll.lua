
require "luaunit"
require "ll"
require "fa_algorithms"
require "bootstrap/rtn"
require "pp"

function find_state(rule, slotnum)
  if slotnum == 0 then
    return rule.start
  end

  for s in each(rule:states()) do
    for edge_val, dest_state, properties in s:transitions() do
      if properties.slotnum == slotnum then
        return s
      end
    end
  end

  error(string.format("No such slotnum (%d) for rule %s", slotnum, rule_str))
end

function get_target_for_slotnum(state, slotnum)
  if slotnum == 0 then
    return {0, 0}
  else
    for edge_val, dest_state, properties in state:transitions() do
      if properties.slotnum == slotnum then
        return {edge_val, dest_state}
      end
    end
  end
  error(string.format("Slotnum %d not found for state %s", slotnum, serialize(state, 4, "  ")))
end

function parse_gla(str, rtn_state)
  local stream = CharStream:new(str)
  stream:ignore("whitespace")
  local gla = fa.GLA:new()
  gla.rtn_state = rtn_state
  local states = {[1]=gla.start}
  while not stream:eof() do
    local statenum = tonumber(stream:consume_pattern("%d+"))
    local state = states[statenum]
    if not state then
      error(string.format("GLA refers to state %d before it is used as a target",
            statenum))
    end
    while stream:lookahead(1) ~= ";" do
      stream:consume("-")
      local term = stream:consume_pattern("%w+")
      stream:consume("->")
      local dest_state_num = tonumber(stream:consume_pattern("%d+"))
      states[dest_state_num] = states[dest_state_num] or fa.GLAState:new()
      local dest_state = states[dest_state_num]
      if term == "EOF" then
        state:add_transition(fa.eof, dest_state)
      else
        state:add_transition(term, dest_state)
      end
      if stream:lookahead(1) == "(" then
        stream:consume("(")
        local final_state_slotnum = tonumber(stream:consume_pattern("%d+"))
        stream:consume(")")
        dest_state.final = get_target_for_slotnum(rtn_state, final_state_slotnum)
      end
      state = dest_state
    end
    stream:consume(";")
  end

  return gla
end

function assert_lookahead(grammar_str, rule_str, slotnum, expected_gla_str)
  grammar = parse_grammar(CharStream:new(grammar_str))
  grammar:determinize_rtns()
  grammar:minimize_rtns()

  local rule = grammar.rtns:get(rule_str)
  state = find_state(rule, slotnum)
  expected_gla = parse_gla(expected_gla_str, state)

  compute_lookahead(grammar)

  if not fa_isequal(expected_gla, state.gla) then
    local bad = io.open("bad.dot", "w")
    bad:write("digraph untitled {\n")
    bad:write(state.gla:to_dot())
    bad:write("}")
    bad:close()

    local good = io.open("good.dot", "w")
    good:write("digraph untitled {\n")
    good:write(expected_gla:to_dot())
    good:write("}")
    good:close()

    os.execute("dot -Tpng -o good.png good.dot")
    os.execute("dot -Tpng -o bad.png bad.dot")

    error("GLAs were not equal: expected and actual are " ..
          "in good.png and bad.png, respectively")
  end
end

TestSimple = {}
function TestSimple:test1()
  assert_lookahead(
  [[
    s -> a | "X";
    a -> "Y";
  ]],
  "s", 0,
  [[
    1 -Y-> 2(1);
    1 -X-> 3(2);
  ]]
  )
end

function TestSimple:test_multiple_recursions()
  assert_lookahead(
  [[
    s -> a | "X";
    a -> b;
    b -> "Y";
  ]],
  "s", 0,
  [[
    1 -Y-> 2(1);
    1 -X-> 3(2);
  ]]
  )
end

TestEpsilon = {}
function TestEpsilon:test1()
  assert_lookahead(
  [[
    s -> a "Z" | "X";
    a -> "Y"?;
  ]],
  "s", 0,
  [[
    1 -Y-> 2(1);
    1 -Z-> 2;
    1 -X-> 3(3);
  ]]
  )
end

function TestEpsilon:test2()
  assert_lookahead(
  [[
    s -> a | "X";
    a -> "Y"? "Z" ;
  ]],
  "s", 0,
  [[
    1 -Y-> 2(1);
    1 -Z-> 2;
    1 -X-> 3(2);
  ]]
  )
end

function TestEpsilon:test3()
  assert_lookahead(
  [[
    s -> a "Q" | "X";
    a -> "Y"? "Z"? ;
  ]],
  "s", 0,
  [[
    1 -Y-> 2(1);
    1 -Z-> 2;
    1 -Q-> 2;
    1 -X-> 3(3);
  ]]
  )
end

function TestEpsilon:test4()
  assert_lookahead(
  [[
    s -> a "Q" | "X";
    a -> b "Y"?;
    b -> "Z"?;
  ]],
  "s", 0,
  [[
    1 -Y-> 2(1);
    1 -Z-> 2;
    1 -Q-> 2;
    1 -X-> 3(3);
  ]]
  )
end

function TestEpsilon:test5()
  assert_lookahead(
  [[
    s -> a "Q" | "X";
    a -> b? "Y"?;
    b -> "Z";
  ]],
  "s", 0,
  [[
    1 -Y-> 2(1);
    1 -Z-> 2;
    1 -Q-> 2;
    1 -X-> 3(3);
  ]]
  )
end

--[=[
  TODO: add this test when GLAs that tell RTNs to return are supported.
function TestEpsilon:test5()
  assert_lookahead(
  [[
    s -> a "X";
    a -> "Y"* "Z";
  ]],
  "a", 1,
  [[
    1 -Y-> 2(1);
    1 -X-> 3(0);
  ]]
  )
end
]=]

TestMultipleNonterms = {}
function TestMultipleNonterms:test1()
  assert_lookahead(
  [[
    s -> a | b | c;
    a -> "X";
    b -> "Y";
    c -> "Z";
  ]],
  "s", 0,
  [[
    1 -X-> 2(1);
    1 -Y-> 3(2);
    1 -Z-> 4(3);
  ]]
  )
end

function TestMultipleNonterms:test22()
  assert_lookahead(
  [[
    s -> (a | b | c)? d;
    a -> "X";
    b -> "Y";
    c -> "Z";
    d -> "Q";
  ]],
  "s", 0,
  [[
    1 -X-> 2(1);
    1 -Y-> 3(2);
    1 -Z-> 4(3);
    1 -Q-> 5(4);
  ]]
  )
end

TestLL2 = {}
function TestLL2:test1()
  assert_lookahead(
  [[
    s -> "X" "Y" | "X" "Z";
  ]],
  "s", 0,
  [[
    1 -X-> 2;
    2 -Y-> 3(1);
    2 -Z-> 4(3);
  ]]
  )
end

function TestLL2:test2()
  assert_lookahead(
  [[
    s -> a "Y" | a "Z";
    a -> "X";
  ]],
  "s", 0,
  [[
    1 -X-> 2;
    2 -Y-> 3(1);
    2 -Z-> 4(3);
  ]]
  )
end

function TestLL2:test3()
  assert_lookahead(
  [[
    s -> a "Y" | a "Z";
    a -> "X" | "Q";
  ]],
  "s", 0,
  [[
    1 -X-> 2;
    1 -Q-> 2;
    2 -Y-> 3(1);
    2 -Z-> 4(3);
  ]]
  )
end

function TestLL2:test3()
  assert_lookahead(
  [[
    s -> "X"? "Y" | "X" "Z";
  ]],
  "s", 0,
  [[
    1 -Y-> 2(2);
    1 -X-> 3;
    3 -Y-> 4(1);
    3 -Z-> 5(3);
  ]]
  )
end

TestLL3 = {}
function TestLL3:test1()
  assert_lookahead(
  [[
    s -> a "X" | a "Y";
    a -> ("P" | "Q") ("P" | "Q");
  ]],
  "s", 0,
  [[
    1 -P-> 2 -P-> 3;
    1 -Q-> 2 -Q-> 3;
    2 -Q-> 3;
    2 -P-> 3;
    3 -X-> 4(1);
    3 -Y-> 5(3);
  ]]
  )
end

function TestLL3:test2()
  assert_lookahead(
  [[
    s -> a "X" | a "Y";
    a -> ("P" | "Q")? ("P" | "Q")?;
  ]],
  "s", 0,
  [[
    1 -X-> 2(1);
    1 -Y-> 3(3);
    1 -P-> 4 -P-> 5;
    4 -Q-> 5;
    1 -Q-> 4 -Q-> 5;
    4 -P-> 5;
    4 -X-> 2;
    4 -Y-> 3;
    5 -X-> 2;
    5 -Y-> 3;
  ]]
  )
end

-- This is equivalent to the grammar on page 271 of The Definitive ANTLR Reference.
function TestLL3:test3()
  assert_lookahead(
  [[
    s -> "X" s "Y" | "X" "X" "Z";
  ]],
  "s", 0,
  [[
    1 -X-> 2 -X-> 3;
    3 -X-> 4(1);
    3 -Z-> 5(4);
  ]]
  )
end

TestEOF = {}
function TestEOF:test1()
  assert_lookahead(
  [[
    s -> "A" | "A" "B";
  ]],
  "s", 0,
  [[
    1 -A-> 2;
    2 -B-> 3(2);
    2 -EOF-> 4(1);
  ]]
  )
end

function TestEOF:test2()
  -- this is the example used by Terence Parr in his discussion of ANTLR 3.0's
  -- lookahead analysis: http://www.antlr.org/blog/antlr3/lookahead.tml
  assert_lookahead(
  [[
    s -> a "A" | a "B";
    a -> "A"?;
  ]],
  "s", 0,
  [[
    1 -A-> 2;
    1 -B-> 3(3);
    2 -B-> 3(3);
    2 -A-> 4(1);
    2 -EOF-> 4(1);
  ]]
  )
end

TestLLStar = {}
function TestLLStar:test1()
  assert_lookahead(
  [[
    s -> a "X" | a "Y";
    a -> "Z"*;
  ]],
  "s", 0,
  [[
    1 -Z-> 1;
    1 -X-> 2(1);
    1 -Y-> 3(3);
  ]]
  )
end

-- Test lookahead that we can only compute correctly if we apply the
-- tail-recursion optimization.
function TestLLStar:test2()
  assert_lookahead(
  [[
    s -> a "X" | a "Y";
    a -> ("Z" a)?;
  ]],
  "s", 0,
  [[
    1 -Z-> 1;
    1 -X-> 2(1);
    1 -Y-> 3(3);
  ]]
  )
end

TestFollow = {}
function TestFollow:test1()
  assert_lookahead(
  [[
    s -> a "X";
    a -> "Y" "Y" | "Y";
  ]],
  "a", 0,
  [[
    1 -Y-> 2;
    2 -Y-> 3(1);
    2 -X-> 4(3);
  ]]
  )
end

function TestFollow:test2()
  assert_lookahead(
  [[
    s -> a "X";
    a -> "Y"?;
  ]],
  "a", 0,
  [[
    1 -Y-> 2(1);
    1 -X-> 3(0);
  ]]
  )
end

function assert_fails_with_error(grammar_str, error_string)
  grammar = parse_grammar(CharStream:new(grammar_str))
  grammar:determinize_rtns()
  grammar:minimize_rtns()

  local success, message = pcall(compute_lookahead, grammar)
  if success then
    error("Failed to fail!")
  elseif not message:find(error_string) then
    error("Failed with wrong message!  Message was supposed to start with "
          .. error_string .. ", instead it was: " .. message)
  end
end

function assert_left_recursive(grammar_str)
  assert_fails_with_error(grammar_str, "Grammar is not LL%(%*%): it is left%-recursive!")
end

TestDetectNonLLStar = {}
function TestDetectNonLLStar:test_left_recursive()
  assert_left_recursive(
  [[
    s -> s? "X";
  ]]
  )
end

function TestDetectNonLLStar:test_left_recursive2()
  assert_left_recursive(
  [[
    s -> a | "X";
    a -> s | "Y";
  ]]
  )
end

LuaUnit:run(unpack(arg))

