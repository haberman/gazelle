--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  tests/test_misc.lua

  Tests for the functionality in misc.lua.

  Copyright (c) 2009 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

require "luaunit"
require "misc"

function assert_fails(func, error_string)
  local success, message = pcall(func)
  if success then
    error("Failed to fail!")
  elseif not message:find(error_string) then
    error("Failed with wrong message!  Message was supposed to contain  "
          .. error_string .. ", but it was: " .. message)
  end
end

TestObject = {}
function TestObject:test1()
  define_class("NoInitializerClass")
  assert_fails(function() local x = NoInitializerClass:new() end,
               "non%-existent method or member 'initialize' on an object of class 'NoInitializerClass'")

  define_class("HasInitializer")
  function HasInitializer:initialize(foo, bar)
    self.foo = foo
    self.bar = bar
    self.baz = nil
  end
  obj = HasInitializer:new(1, 2)
  assert_equals(1, obj.foo)
  assert_equals(2, obj.bar)
  obj.baz = 3
  assert_equals(3, obj.baz)
  assert_fails(function() obj.quux = 3 end,
               "Attempted to assign property 'quux' to an object of class 'HasInitializer'")

  define_class("HasMethods")
  function HasMethods:initialize()
    self.x = nil
  end

  function HasMethods:foo(x)
    self.x = x
  end

  obj = HasMethods:new()
  obj:foo(10)
  assert_equals(10, obj.x)

  define_class("InheritsInitialize", HasMethods)
  function InheritsInitialize:calls_foo()
    self:foo(15)
  end
  obj = InheritsInitialize:new()
  obj:calls_foo()
  assert_equals(15, obj.x)

  define_class("OverridesInitialize", HasMethods)
  function OverridesInitialize:initialize()
    HasMethods.initialize(self)
  end

  function OverridesInitialize:calls_foo()
    self:foo(20)
  end
  obj = OverridesInitialize:new()
  obj:calls_foo()
  assert_equals(20, obj.x)
end

