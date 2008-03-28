
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
  for edge_val, dest_state, properties in state:transitions() do
    if properties.slotnum == slotnum then
      return {edge_val, dest_state}
    end
  end
  error(string.format("Slotnum %d not found for state %s", slotnum, serialize(state, 4, "  ")))
end

function parse_gla(str, rtn_state)
  local stream = CharStream:new(str)
  stream:ignore("whitespace")
  local gla = fa.GLA:new()
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
      state:add_transition(term, dest_state)
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
    error(string.format("GLAs were not equal: expected=%s, actual=%s",
                        expected_gla:to_dot(), state.gla:to_dot()))
  end
end

TestLookahead = {}

function TestLookahead:test_simple()
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

function TestLookahead:test_multiple_recursions()
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

function TestLookahead:test_simple_epsilon()
  assert_lookahead(
  [[
    s -> a "Z" | "X";
    a -> "Y"?;
  ]],
  "s", 0,
  [[
    1 -Y-> 2(1);
    1 -Z-> 3(1);
    1 -X-> 4(3);
  ]]
  )
end

function TestLookahead:test_simple_epsilon2()
  assert_lookahead(
  [[
    s -> a | "X";
    a -> "Y"? "Z" ;
  ]],
  "s", 0,
  [[
    1 -Y-> 2(1);
    1 -Z-> 3(1);
    1 -X-> 4(2);
  ]]
  )
end

function TestLookahead:test_simple_epsilon3()
  assert_lookahead(
  [[
    s -> a "Q" | "X";
    a -> "Y"? "Z"? ;
  ]],
  "s", 0,
  [[
    1 -Y-> 2(1);
    1 -Z-> 3(1);
    1 -Q-> 4(1);
    1 -X-> 5(3);
  ]]
  )
end

function TestLookahead:test_simple_epsilon4()
  assert_lookahead(
  [[
    s -> a "Q" | "X";
    a -> b "Y"?;
    b -> "Z"?;
  ]],
  "s", 0,
  [[
    1 -Y-> 2(1);
    1 -Z-> 3(1);
    1 -Q-> 4(1);
    1 -X-> 5(3);
  ]]
  )
end

function TestLookahead:test_simple_epsilon5()
  assert_lookahead(
  [[
    s -> a "Q" | "X";
    a -> b? "Y"?;
    b -> "Z";
  ]],
  "s", 0,
  [[
    1 -Y-> 2(1);
    1 -Z-> 3(1);
    1 -Q-> 4(1);
    1 -X-> 5(3);
  ]]
  )
end

function TestLookahead:test_multiple_nonterms()
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

function TestLookahead:test_multiple_nonterms2()
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

function TestLookahead:test_ll_2()
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


LuaUnit:run()

