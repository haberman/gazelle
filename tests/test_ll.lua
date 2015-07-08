--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  tests/test_ll.lua

  Tests for the LL(*) lookahead generation.  This is the among the
  most complicated things the complier does, and it has a lot of edge
  cases and failure modes, so this file is complicated and subtle.

--------------------------------------------------------------------]]--

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
  error(string.format("Slotnum %d not found for state %s", slotnum, serialize(state, 6, "  ")))
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

function assert_lookahead(grammar_str, rule_str, slotnum, expected_gla_str, k)
  local grammar = Grammar:new()
  grammar:parse_source_string(grammar_str)
  grammar:process()

  local rule = grammar.rtns:get(rule_str)
  local state = find_state(rule, slotnum)
  local expected_gla = parse_gla(expected_gla_str, state)

  grammar:compute_lookahead(k)

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

TestLL1 = {}
function TestLL1:test1()
  assert_lookahead(
  [[
    s -> "X" s?;
  ]],
  "s", 2,
  [[
    1 -X-> 2(2);
    1 -EOF-> 3(0);
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

function TestLL2:test3()
  assert_lookahead(
  [[
    s -> "X" s | "X" "Y";
  ]],
  "s", 0,
  [[
    1 -X-> 2 -X-> 3(1);
    2 -Y-> 4(3);
  ]]
  )
end

function TestLL2:test4()
  assert_lookahead(
  [[
    a -> b "X";
    b -> c*;
    c -> "X";
  ]],
  "b", 0,
  [[
    1 -X-> 2 -X-> 3(1);
    2 -EOF-> 4(0);
  ]]
  )
end

function TestLL2:test5()
  assert_lookahead(
  [[
    s -> "X"+ | "X" "Y";
  ]],
  "s", 0,
  [[
    1 -X-> 2 -X-> 3(1);
    2 -EOF-> 3;
    2 -Y-> 4(2);
  ]]
  )
end

function TestLL2:test6()
  assert_lookahead(
  [[
    s -> a? "X" "X";
    a -> "X" "Y" | "X" "Z";
  ]],
  "s", 0,
  [[
    1 -X-> 2 -X-> 3(2);
    2 -Y-> 4(1);
    2 -Z-> 4;
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

function TestLL3:test3()
  assert_lookahead(
  [[
    s -> a a "Y" | a a "Z";
    a -> "X";
  ]],
  "s", 0,
  [[
    1 -X-> 2 -X-> 3 -Y-> 4(1);
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

function TestEOF:test3()
  assert_lookahead(
  [[
    s -> "A" a;
    a -> "A"?;
  ]],
  "a", 0,
  [[
    1 -A-> 2(1);
    1 -EOF-> 3(0);
  ]]
  )
end

-- This is really a "follow" test
function TestEOF:test4()
  assert_lookahead(
  [[
    s -> "X" a "Y";
    a -> b;
    b -> "X"?;
  ]],
  "b", 0,
  [[
    1 -X-> 2(1);
    1 -Y-> 3(0);
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

-- A GLA cycle that occurs in a state that is more than 1 transition
-- away from the start (there used to be a bug that caused an infinite
-- loop in this case).
function TestLLStar:test3()
  assert_lookahead(
  [[
    s -> "X" "Y" "Z"* "Q" | "X" "Y" "Z"* "R";
  ]],
  "s", 0,
  [[
    1 -X-> 2;
    2 -Y-> 3;
    3 -Z-> 3;
    3 -Q-> 4(1);
    3 -R-> 5(5);
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
  local grammar = Grammar:new()
  grammar:parse_source_string(grammar_str)
  grammar:process()

  local success, message = pcall(grammar.compute_lookahead, grammar)
  if success then
    error("Failed to fail!")
  elseif not message:find(error_string) then
    error("Failed with wrong message!  Message was supposed to contain  "
          .. error_string .. ", but it was: " .. message)
  end
end

function assert_left_recursive(grammar_str)
  assert_fails_with_error(grammar_str, "it is left%-recursive")
end

function assert_nonregular(grammar_str)
  assert_fails_with_error(grammar_str, "one lookahead language was nonregular, others were not all fixed")
end

function assert_ambiguous(grammar_str)
  assert_fails_with_error(grammar_str, "Ambiguous grammar")
end

function assert_no_nonrecursive_alt(grammar_str)
  assert_fails_with_error(grammar_str, "no non%-recursive alternative")
end

function assert_not_ll(grammar_str)
  assert_fails_with_error(grammar_str, "It is not Strong%-LL or full%-LL")
end

function assert_never_taken(grammar_str)
  assert_fails_with_error(grammar_str, "will never be taken")
end

function assert_resolution_not_supported(grammar_str)
  assert_fails_with_error(grammar_str, "cannot support this resolution of the ambiguity")
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

function TestDetectNonLLStar:test_left_recursive3()
  assert_left_recursive(
  [[
    s -> (s "X")?;
  ]]
  )
end

-- Hmm, technically this test is broken because this is left-recursion
-- that is getting incorrectly reported as ambiguity instead.  But
-- fixing this one isn't a high priority right now.
-- function TestDetectNonLLStar:test_left_recursive4()
--   assert_left_recursive(
--   [[
--     s -> a b?;
--     a -> "X"?;
--     b -> s;
--   ]]
--   )
-- end

function TestDetectNonLLStar:test_nonregular()
  assert_nonregular(
  [[
    s -> e "%" | e "!";
    e -> "(" e ")" | "ID";
  ]]
  )
end

function TestDetectNonLLStar:test_fails_heuristic_but_is_ll()
  assert_nonregular(
  [[
    s -> "X"* "Y" "Y" "Z"| "X" c;
    c -> "Y" c "Y" | "Q";
  ]]
  )
  assert_lookahead(
  [[
    s -> "X"* "Y" "Y" "Z"| "X" c;
    c -> "Y" c "Y" | "Q";
  ]],
  "s", 0,
  [[
    1 -Y-> 2(2);
    1 -X-> 3 -Y-> 4 -Y-> 5 -Y-> 6(5);
    3 -Q-> 6;
    4 -Q-> 6;
    5 -Q-> 6;
    5 -Z-> 7(1);
    3 -X-> 7;
  ]],
  4
  )
end

function TestDetectNonLLStar:test_not_full_ll_1()
  assert_not_ll(
  [[
    s -> a a;
    a -> b;
    b -> "X"*;
  ]]
  )
end

function TestDetectNonLLStar:test_not_full_ll_1()
  assert_not_ll(
  [[
    s -> ("X" s "X")?;
  ]]
  )
end

function TestDetectNonLLStar:test_not_full_ll_2()
  assert_not_ll(
  [[
    s -> "if" e "then" s ("else" s)? | e;
    e -> "5";
  ]]
  )
end


TestAmbiguity = {}
function TestAmbiguity:test1()
  assert_ambiguous(
  [[
    a -> b | c;
    b -> c;
    c -> "X";
  ]]
  )
end

function TestAmbiguity:test2()
  assert_ambiguous(
  [[
    a -> b c "Y";
    b -> "X" ?;
    c -> "X" ?;
  ]]
  )
end

function TestAmbiguity:test3()
  assert_ambiguous(
  [[
    a -> (b | c) "Y";
    b -> "X";
    c -> "X";
  ]]
  )
end

function TestAmbiguity:test4()
  assert_ambiguous(
  [[
    s -> a "X"?;
    a -> "X"?;
  ]]
  )
end

function TestAmbiguity:test5()
  assert_ambiguous(
  [[
    s -> a "X"*;
    a -> "X"*;
  ]]
  )
end

function TestAmbiguity:test6()
  assert_ambiguous(
  [[
    s -> a? a?;
    a -> "X";
  ]]
  )
end

function TestAmbiguity:test7()
  assert_ambiguous(
  [[
    s -> "X" | "X";
  ]]
  )
end

function TestAmbiguity:test8()
  assert_ambiguous(
  [[
    s -> "X"? | "X";
  ]]
  )
end

function TestAmbiguity:test9()
  assert_ambiguous(
  [[
    s -> "X"? | "X"?;
  ]]
  )
end

function TestAmbiguity:test10()
  assert_ambiguous(
  [[
    s -> a b;
    a -> "X"*;
    b -> "X"*;
  ]]
  )
end

function TestAmbiguity:test11()
  assert_ambiguous(
  [[
    s -> a*;
    a -> "X"?;
  ]]
  )
end

function TestAmbiguity:test12()
  assert_ambiguous(
  [[
    s -> a*;
    a -> "X"*;
  ]]
  )
end

-- These tests are currently failing because I have not implemented this
-- check yet!
TestNoNonRecursiveAlt = {}
function TestNoNonRecursiveAlt:test1()
  assert_no_nonrecursive_alt(
  [[
    a -> a;
  ]]
  )
end

function TestNoNonRecursiveAlt:test2()
  assert_no_nonrecursive_alt(
  [[
    a -> "X" a;
  ]]
  )
end

function TestNoNonRecursiveAlt:test3()
  assert_no_nonrecursive_alt(
  [[
    a -> "X" b;
    b -> a;
  ]]
  )
end

function TestNoNonRecursiveAlt:test4()
  assert_no_nonrecursive_alt(
  [[
    s -> a b;
    a -> "X"?;
    b -> s;
  ]]
  )
end

function TestNoNonRecursiveAlt:test4()
  assert_no_nonrecursive_alt(
  [[
    a -> "X" b;
    b -> "X" a;
  ]]
  )
end

TestAmbiguityResolution = {}
function TestAmbiguityResolution:test1()
  assert_lookahead(
  [[
    s -> "X" "Y" / "X"+ "Y";
  ]],
  "s", 0,
  [[
    1 -X-> 2 -Y-> 3(1);
    2 -X-> 4(3);
  ]]
  )
end

function TestAmbiguityResolution:test2()
  assert_lookahead(
  [[
    s -> "if" e "then" s ("else" s)?+ | e;
    e -> "5";
  ]],
  "s", 5,
  [[
    1 -else-> 2(5);
    1 -EOF-> 3(0);
  ]]
  )
end

function TestAmbiguityResolution:test_never_taken1()
  assert_never_taken(
  [[
    s -> "X" "Y" / "X" "Y";
  ]]
  )
end

-- This test is currently failing -- it's throwing the wrong error message.
-- Instead of warning you that one transition is never taken, it just says
-- that Gazelle can't support this resolution of the ambiguity.
function TestAmbiguityResolution:test_never_taken2()
  assert_never_taken(
  [[
    s -> a b / "X" "Y";
    a -> "X";
    b -> "Y";
  ]]
  )
end

function TestAmbiguityResolution:test_never_taken3()
  assert_never_taken(
  [[
    s -> "X"* "Y" / "X" "Y";
  ]]
  )
end

function TestAmbiguityResolution:test_resolution_not_supported1()
  assert_resolution_not_supported(
  [[
    s -> "S" / "S" s "S";
  ]]
  )
end

function TestDetectNonLLStar:test_resolution_not_supported2()
  assert_resolution_not_supported(
  [[
    s -> "if" e "then" s ("else" s)?- | e;
    e -> "5";
  ]]
  )
end

