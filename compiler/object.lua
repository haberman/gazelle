--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  object.lua

  A lightweight object library for object-oriented programming.  Heavily
  inspired by Ruby.

  It would be easy to get carried away and go all out on this, using
  __index and __newindex everywhere to do all sorts of crazy things.  I
  have very pragmatic goals:

  - encapsulation.  when I look at a class I want to know that there
    isn't random code twiddling the instance variables.
  - making properties go through get_foo() and set_foo() methods, so
    I have a well-defined set of properties for each object.  I'm fine
    with adding properties to objects, I just want a list of them.
  - (related to the previous) catching typos on method calls.

  The goal is *not* to make objects "secure" against outside tampering.
  It's to prevent you from doing it by accident.

  So the main features I provide are:
  - encapsulation: obj.foo is *not* that object's self.foo.
  - classes are objects that can have methods and instance variables.
  - single inheritance.
  - nice errors when you try to call an undefined method, eg. "Class
    Foo has no method named Bar", instead of an error trying to make
    a function call on nil.

  In an earlier version I supported properties
  (eg. "obj.foo = bar" calls obj:set_foo(bar)), but this turned out to
  introduce more complexity than I could stomach (even without them
  the implementation is more complex than I would prefer).

  Usage:

  -- to call a method on an object:
  obj:method(args)

  -- to create a new class, you call "new" on Class.
  -- this will assign the class to ObjectName in the global namespace.
  Class:new("ObjectName", ParentClass)

  -- to define methods on your new class
  function ObjectName:method(foo, bar)
    self.foo = foo
  end

  -- to define an initializer (method called when the object is constructed)
  function ObjectName:initialize(foo, bar)
    self.foo = foo
  end

  -- to construct an instance of your new class.
  obj = ObjectName:new("foo", "bar")
  obj.foo  -- not the same as self.foo, to gain encapsulation

  -- setting random properties on objects is not allowed:
  obj.foo = "bar" -- throws error "Setting properties on an object is not allowed!"

  -- to have properties, use get_foo() and set_foo() methods.
  -- if you just want simple wrappers around instance variables, use
  -- attr_reader, attr_writer, and attr_accessor, which will generate
  -- trivial versions of these methods for you:
  attr_accessor(ObjectName, "foo")
  obj.get_foo()
  obj.set_foo("foo")

  One thing that is *not* supported is adding methods to classes in an
  unexpected order.  For example, if you do:

  Class:new("Base")
  Class:new("Derived", Base)
  function Derived:method()
    self:super()
  end

  function Base:method()
  end

  ...super() in the Derived method will NOT work properly.

  Copyright (c) 2009 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

--[[--------------------------------------------------------------------

  Handy function for creating get_foo()/set_foo() methods.  Inpired
  by the Ruby functions of the same name.

--------------------------------------------------------------------]]--

function attr_reader(obj_methods, name)
  obj_methods["get_" .. name] = function(self)
    return self[name]
  end
end

function attr_writer(obj_methods, name)
  obj_methods["set_" .. name] = function(self, value)
    self[name] = value
  end
end

function attr_accessor(obj_methods, name)
  attr_reader(obj_methods, name)
  attr_writer(obj_methods, name)
end

-- Tests whether a value is an object from this library.
function isobject(val)
  return type(val) == "table" and
    (rawget(val, "__self") or rawget(val, "public_obj"))
end

--[[--------------------------------------------------------------------

  The primary characteristic of this object library is that every
  method that a user defines on an object is wrapped by a function
  that pulls __self (which holds the instance variables) out of the
  public object.  We then use wrap_method_call as the __newindex
  in each class's metatable, so that when a user defines a function
  it gets this wrapper.

  The scheme is:

  Object instances look like: {
    singleton_method = function()
    __self = {
      public_obj = me  -- a way to get at myself from inside methods
      class = <my class>
      -- other instance variables that the class uses.
      <metatable> = {
        -- This lets me say self:method().
        __index = <my class>.__self.instance_methods
      }
    }
    <metatable> = {
      __index = <my class>.__self.instance_methods
      __newindex = <function that wraps singleton methods>
    }
  }

  Classes are objects, but in addition to the above also have: {
    __self = {
      name = "ClassName"
      superclass = ClassSuperclass (nil for Object)
      instance_methods = {
        method1 = function()
        <metatable> = {
          __index = superclass.__self.instance_methods
        }
      }
      instance_mt = {
        -- the metatable shared by all instances of this class,
        -- with contents as above (in Object).
      }
      private_instance_mt = {
        -- the metatable shared by all __self's of this class,
        -- with contents as above (in Object).
      }
    }
    <metatable> = {
      __index = <my class (Class)>.__self.instance_methods
      __newindex = <function that wraps instance methods>
    }
  }

--------------------------------------------------------------------]]--

function get_receiver(obj)
  -- "obj" can be either the public object (if we were called regularly)
  -- or the instance variables (if we were called from within a method,
  -- using self:foo()).
  if not obj then
    error("Called instance method without passing a receiver " ..
          "(did you forget the colon?)")
  end
  local receiver = (type(obj) == "table" and rawget(obj, "__self")) or obj
  if type(obj) == "table" and rawget(receiver, "class") then
    return receiver
  else
    -- We have a first argument, but it's not an object -- we probably
    -- got called as obj.method(foo), and we got "foo" as self instead
    -- of "obj".
    error("Called instance method without passing a receiver " ..
          "(did you forget the colon?)")
  end
end

function wrap_singleton_method_call(public_obj, key, method)
  if type(method) == "function" then
    rawset(public_obj, key, function(obj, ...)
      return method(get_receiver(obj), ...)
    end)
  else
    error("Setting properties on an object is not allowed " ..
          "(create getter/setter methods instead)")
  end
end

function no_superclass_method(method, class_self)
  return function()
    error(string.format("Tried to call super from %s:%s, but no superclasses " ..
                        "have this method defined", class.name, method))
  end
end

function wrap_instance_method_call(self)
  return function(public_obj, key, value)
    if type(value) == "function" then
      rawget(public_obj, "__self").instance_methods[key] = function(obj, ...)
        local receiver = get_receiver(obj)
        local saved_super = receiver.super
        receiver.super = self.superclass and self.superclass.__self.instance_methods[key]
        receiver.super = receiver.super or no_superclass_method(key, self)
        local ret = {value(receiver, ...)}
        receiver.super = saved_super
        return unpack(ret)
      end
    else
      error("Setting properties on an object is not allowed " ..
            "(create getter/setter methods instead)")
    end
  end
end

function get_instance_method_or_error(instance_methods)
  return function(public_obj, method_name)
    local method = instance_methods[method_name]
    if not method then
      error(string.format("Class '%s' has no method named '%s'",
                          public_obj.__self.class.__self.name,
                          method_name))
    end
    return method
  end
end

--[[--------------------------------------------------------------------

  Creating the "Class" and "Object objects class has to be
  special-cased.  We can't use Class:new (since it doesn't
  exist yet).  We perform the equivalent of Class:new(), but
  gerry-rig the process to result with:
  - Class's class is Class
  - Class derives from Object

--------------------------------------------------------------------]]--
Class = {}
Class.__self = {public_obj=Class, class=Class, instance_methods={}}
setmetatable(Class, {
  __index = Class.__self.instance_methods,
  __newindex = wrap_instance_method_call(Class.__self)
})

-- Class definition:
  attr_reader(Class, "metatable")
  attr_reader(Class, "superclass")
  attr_reader(Class, "name")

  function Class:new(...)
    local new_obj = {}
    new_obj.__self = {public_obj=new_obj, class=self.public_obj}
    setmetatable(new_obj, self.instance_mt)
    setmetatable(new_obj.__self, self.private_instance_mt)
    new_obj:initialize(...)
    return new_obj
  end

  function Class:initialize(name, superclass)
    _G[name] = self.public_obj
    self.name = name
    if name ~= "Class" then
      self.instance_methods = {}
    end
    if name ~= "Object" and name ~= "Class" then
      self.superclass = superclass or Object
      -- In general this is correct for Class, except that its
      -- superclass (Object) isn't set because it hasn't been
      -- created yet.
      --
      -- For Object, we want to just return nil if the instance
      -- method isn't found, because Object has no superclass so
      -- there's nowhere else to look.
      setmetatable(self.instance_methods, {
        __index = self.superclass.__self.instance_methods
      })
    end

    self.instance_mt = {
      __index = get_instance_method_or_error(self.instance_methods),
      __newindex = wrap_singleton_method_call,
      __tostring = function(public_obj) return public_obj:tostring() end
    }
    -- This lets methods call other methods by doing self:foo().
    self.private_instance_mt = {
      __index = self.instance_methods,
      __tostring = function(obj) return obj:tostring() end
    }

    getmetatable(self.public_obj).__newindex = wrap_instance_method_call(self)
  end

  function Class:def_class_method(name, def)
    wrap_singleton_method_call(self.public_obj, name, def)
  end

  function Class:tostring()
    return string.format("<Class '%s'>", self.name)
  end

-- Finish Class's initialization by running initialize() and
-- giving it the appropriate metatables.
Class.__self.instance_methods.initialize(Class.__self, "Class")
setmetatable(Class, Class.__self.instance_mt)
setmetatable(Class.__self, Class.__self.private_instance_mt)

-- Now define Object, and make it Class's parent.
Class:new("Object")
  attr_accessor(Object, "class")

  function Object:initialize()
    -- for classes that don't define initialize(): do nothing.
  end

  function Object:tostring()
    local str = ""
    local first = true
    for k,v in pairs(self) do
      if k ~= "class" and k ~= "public_obj" and k ~= "super" then
        if first then
          first = false
        else
          str = str .. ", "
        end
        str = str .. string.format("%s=%s", tostring(k), tostring(v))
      end
    end
    return string.format("<Object of class %s, instance vars={%s}>",
                         self.class:get_name(), str)
  end

  function Object:object_id()
    -- this is hacky, but I don't know a better way.
    -- it's arbitrary whether we use the public or the private table.  either
    -- should work fine as long as it's consistent.
    local saved_mt = getmetatable(self)
    setmetatable(self, nil)
    local str = tostring(self)
    setmetatable(self, saved_mt)
    return str
  end

rawget(Class, "__self").superclass = Object
setmetatable(rawget(Class, "__self").instance_methods, {
  __index = rawget(Object, "__self").instance_methods
})

