--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  tests/test_minimize.lua

  Tests for NFA -> DFA conversion.

  Copyright (c) 2009 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

require "luaunit"
require "data_structures"
require "fa"
require "fa_algorithms"

TestDeterminize = {}
function TestDeterminize:test1()
  local rtn = fa.RTN:new()
  local start_state = rtn:get_start()
  local final_state = rtn:get_final()
  local other_state = rtn:new_state()
  start_state:add_transition("X", other_state)
  other_state:add_transition(fa.e, final_state)
  final_state:set_final(true)

  local dfa = nfa_to_dfa(rtn)
  local expect_rtn = fa.RTN:new()
  local expect_start = expect_rtn:get_start()
  local expect_final = expect_rtn:get_final()
  expect_start:add_transition("X", expect_final)
  expect_final:set_final(true)
  assert_equals(true, fa_isequal(dfa, expect_rtn))
end

