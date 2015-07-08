--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  tests/test_data_structures.lua

  Routines that test data structures like stacks, queues, etc.

--------------------------------------------------------------------]]--

require "luaunit"
require "data_structures"

TestQueue = {}
  function TestQueue:test_initial_state()
    local queue = Queue:new()
    assert_equals(true, queue:isempty())
    assert_error(function() queue:dequeue() end)
  end

  function TestQueue:test_fifo_behavior()
    local queue = Queue:new()
    local list = {1, 2, 3, 4, 5}
    for e in each(list) do
      queue:enqueue(e)
      assert_equals(false, queue:isempty())
    end

    for e in each(list) do
      assert_equals(false, queue:isempty())
      assert_equals(e, queue:dequeue())
    end

    assert_equals(true, queue:isempty())
  end
-- class TestQueue

TestSet = {}
  function TestSet:test_initial_state()
    local set = Set:new()
    assert_equals(true, set:isempty())
    assert_equals(0, set:count())
    assert_equals({}, set:to_array())
    assert_equals(false, set:contains(5))
    assert_equals(set:hash_key(), set:hash_key())
    for _ in set:each() do
      assert_fail()
    end
  end

  function _test_contains_one_value(set, val)
    assert_equals(false, set:isempty())
    assert_equals(1, set:count())
    assert_equals({val}, set:to_array())
    assert_equals(true, set:contains(val))
    assert_equals(set:hash_key(), set:hash_key())
    for elem in set:each() do
      assert_equals(val, elem)
    end
  end

  function TestSet:test_add_element()
    local set = Set:new()
    set:add(5)
    _test_contains_one_value(set, 5)
  end

  function TestSet:test_remove_element()
    local set = Set:new()
    local val = {foo="bar"}
    set:add(5)
    set:add(val)
    set:remove(5)
    _test_contains_one_value(set, val)
  end

  function TestSet:test_add_collection()
    local set = Set:new()
    local values = {1, 2, 3, 4, 5}
    set:add_collection(values)
    assert_equals(false, set:isempty())
    assert_equals(5, set:count())
    assert_equals(values, set:to_array())
    for val in each(values) do
      assert_equals(true, set:contains(val))
    end
    assert_equals(set:hash_key(), set:hash_key())
  end
-- class TestQueue

TestRange = {}
  function TestRange:test_initial_state()
    local range = Range:new(5, 10)
    assert_equals(5, range.low)
    assert_equals(10, range.high)
    assert_equals(true, range:contains(5))
    assert_equals(true, range:contains(7))
    assert_equals(true, range:contains(10))
  end

  function TestRange:test_single_int_range()
    local range = Range:new(3, 3)
    assert_equals(true, range:contains(3))
  end

  function TestRange:test_invalid_construction()
    assert_error(function () Range:new(5, 4) end)
    assert_error(function () Range:new(5) end)
    assert_error(function () Range:new() end)
  end

  function TestRange:test_union()
    assert_equals(nil, Range:new(2, 4):union(Range:new(6, 7)))
    assert_equals(nil, Range:new(2, 4):union(Range:new(6, 7)))

    local union = Range:new(2, 4):union(Range:new(5, 7))
    assert_equals(2, union.low)
    assert_equals(7, union.high)

    union = Range:new(1, 4):union(Range:new(2, 3))
    assert_equals(1, union.low)
    assert_equals(4, union.high)

    union = Range:new(1, 5):union(Range:new(3, 7))
    assert_equals(1, union.low)
    assert_equals(7, union.high)
  end

TestIntSet = {}
  function TestIntSet:test_initial_state()
    local int_set = IntSet:new()
    assert_equals(false, int_set.negated)
    assert_equals(false, int_set:contains(0))
    assert_equals(false, int_set:contains(20))
    assert_equals(false, int_set:contains(math.huge))
    assert_equals(nil, int_set:sampleint())
  end

  function TestIntSet:test_adding_one_range()
    local int_set = IntSet:new()
    int_set:add(Range:new(3, 6))

    assert_equals(false, int_set.negated)
    assert_equals(false, int_set:contains(2))
    assert_equals(false, int_set:contains(7))
    assert_equals(true, int_set:contains(3))
    assert_equals(true, int_set:contains(6))
    assert_equals(true, int_set:contains(5))

    assert_equals(true, int_set:contains(int_set:sampleint()))
  end

  function TestIntSet:test_adding_multiple_range()
    local int_set = IntSet:new()
    int_set:add(Range:new(3, 6))
    int_set:add(Range:new(9, 10))

    assert_equals(false, int_set:contains(2))
    assert_equals(true, int_set:contains(3))
    assert_equals(true, int_set:contains(6))
    assert_equals(false, int_set:contains(7))
    assert_equals(true, int_set:contains(9))
    assert_equals(true, int_set:contains(10))
    assert_equals(false, int_set:contains(11))
  end

  function TestIntSet:test_adding_overlapping_intset()
    local int_set1 = IntSet:new()
    int_set1:add(Range:new(1, 2))
    int_set1:add(Range:new(4, 5))
    int_set1:add(Range:new(7, 15))

    local int_set2 = IntSet:new()
    int_set2:add(Range:new(3, 3))
    int_set2:add(Range:new(6, 20))
    int_set2:add(Range:new(30, 32))

    int_set1:add_intset(int_set2)
    assert_equals("1-20,30-32", int_set1:tointstring())
  end

  function TestIntSet:test_negation()
    local int_set1 = IntSet:new()
    int_set1:add(Range:new(3, 5))
    assert_equals("^0-2,6-inf", int_set1:invert():tointstring())

    local int_set2 = IntSet:new()
    int_set2:add(Range:new(3, 5))
    int_set2:add(Range:new(10, math.huge))
    int_set2.negated = true
    assert_equals("0-2,6-9", int_set2:invert():tointstring())
  end

