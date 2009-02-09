--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  tests/test_minimize.lua

  Tests for the object library.

  Copyright (c) 2009 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

require "luaunit"
require "object"

TestObject = {}
function TestObject:test1()
  Class:new("Greeter")
    function Greeter:initialize(greeting)
      self.greeting = greeting
    end

    function Greeter:greeting()
      return self.greeting
    end

    function Greeter:got_arguments(a, b, c)
      assert_equals("one", a)
      assert_equals(nil, b)
      assert_equals(3, c)
    end

  local greeter = Greeter:new("Hello, world!")
  assert_equals("Hello, world!", greeter:greeting())
  assert_equals(true, Greeter == greeter:get_class())
  greeter:got_arguments("one", nil, 3)
end

function TestObject:test_inheritance()
  Class:new("BaseClass")
    function BaseClass:initialize()
      self.foo = "Foo"
    end

    function BaseClass:verify_foo_called()
      assert_equals("Foo", self.foo)
    end

    function BaseClass:method()
      return "base"
    end

    function BaseClass:delegate()
      return self:method()
    end

    function BaseClass:base_method(foo)
      return "base " .. foo
    end

  Class:new("DerivedClass", BaseClass)
    function DerivedClass:method()
      return "derived"
    end

    function DerivedClass:base_method()
      -- Test that super is preserved across other method calls.
      self:method()
      return self:super("derived extra")
    end

  local base = BaseClass:new()
  local derived = DerivedClass:new()

  assert_equals("base", base:method())
  assert_equals("base", base:delegate())
  assert_equals("derived", derived:method())
  assert_equals("derived", derived:delegate())
  assert_equals("base derived extra", derived:base_method())
  derived:verify_foo_called()
end

function TestObject:test_iterator()
  Class:new("Iterator")
    function Iterator:initialize(list)
      self.list = list
    end

    function Iterator:each()
      return ipairs(self.list)
    end

  local list = {1, 2, 3}
  local iterator = Iterator:new(list)
  local duplicate_list = {}
  for item in iterator:each() do
    table.insert(duplicate_list, item)
  end
  assert_equals(list[1], duplicate_list[1])
  assert_equals(list[2], duplicate_list[2])
  assert_equals(list[3], duplicate_list[3])
end

-- TODO: test that assigning to object properties is prohibited.
