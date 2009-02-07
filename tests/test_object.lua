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
  define_class("Greeter", nil, function(obj)
    function obj:initialize(greeting)
      self.greeting = greeting
    end

    function obj:greeting()
      return self.greeting
    end
  end)

  local greeter = Greeter:new("Hello, world!")
  assert(greeter:greeting() == "Hello, world!")
end

function TestObject:test_properties()
  define_class("PropertyObj", nil, function(obj)
    attr_accessor(obj, "property")

    function obj:verify_five()
      assert(self.property == 5)
    end

    function obj:got_arguments(a, b, c)
      assert(a == "one")
      assert(b == nil)
      assert(c == 3)
    end
  end)

  local obj = PropertyObj:new()
  assert(obj.property == nil)
  obj.property = 5
  assert(obj.property == 5)
  obj:verify_five()
  obj:got_arguments("one", nil, 3)
end

function TestObject:test_class_methods()
  define_class("ClassMethodClass", nil, function(obj, class, class_self)
    class_self.foo = "Foo!"

    function class:get_foo()
      return self.foo
    end

    function obj:get_class_foo()
      return self.class:get_foo()
    end
  end)

  assert(ClassMethodClass:get_foo() == "Foo!")
  local x = ClassMethodClass:new()
  assert(x:get_class_foo() == "Foo!")
end

function TestObject:test_inheritance()
  define_class("BaseClass", nil, function(obj)
    function obj:method()
      return "base"
    end

    function obj:delegate()
      return self:method()
    end
  end)

  define_class("DerivedClass", BaseClass, function(obj)
    function obj:method()
      return "derived"
    end
  end)

  local base = BaseClass:new()
  local derived = DerivedClass:new()

  assert(base:method() == "base")
  assert(base:delegate() == "base")
  assert(derived:method() == "derived")
  assert(derived:delegate() == "derived")
end

LuaUnit:run(unpack(arg))
