--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  tests/test_minimize.lua

  Tests for DFA minimization.

  Copyright (c) 2009 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

require "luaunit"
require "data_structures"
require "fa"
require "fa_algorithms"

TestProperties = {}
-- Tests that different transitions with the same edge values and the same
-- properties are considered equivalent.
function TestProperties:test1()
  local rtn = fa.RTN:new()
  local properties = {}
  local start_state = rtn.start
  local other_state = rtn:new_state()
  start_state:add_transition("X", other_state, properties)
  start_state:add_transition("Y", start_state, properties)
  other_state:add_transition("X", other_state, properties)
  other_state:add_transition("Y", start_state, properties)
  start_state.final = true
  other_state.final = true

  local minimized_rtn = hopcroft_minimize(rtn)
  local expect_rtn = fa.RTN:new()
  local expect_start = expect_rtn.start
  expect_start.final = true
  expect_start:add_transition("X", expect_start, properties)
  expect_start:add_transition("Y", expect_start, properties)
  assert(fa_isequal(minimized_rtn, expect_rtn))
end

LuaUnit:run(unpack(arg))
