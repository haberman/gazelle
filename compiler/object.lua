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
  - having a well-defined set of properties for each object.  I'm fine
    with adding properties to objects, I just want a list of them.
  - (related to the previous) catching typos on object properties.

  The goal is *not* to make objects "secure" against outside tampering.
  It's to prevent you from doing it by accident.

  So the main features I provide are:
  - encapsulation: obj.foo is *not* that object's self.foo.
  - properties: "obj.foo = bar" calls obj:set_foo(bar).
  - classes are objects that can themselves have methods.
  - single inheritance.

  Copyright (c) 2009 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

function define_class(name, superclass, define_func)
  assert(type(name) == "string")
  assert(type(define_func) == "function")
  assert(not _G[name], string.format("Class '%s' redeclared", name))
  if name == "Class" then
    -- Creating the "Class" class has to be special-cased, because we
    -- can't use Class:new (since it doesn't exist yet).
    local class_methods = {}
    define_func({}, class_methods, nil)
    local class = {__instance_vars = {}}
    class.__instance_vars.public_obj = class
    class.__instance_vars.class = class
    -- This will call define_func again, but that shouldn't be a
    -- problem.
    class_methods.initialize(
        class.__instance_vars, name, superclass, define_func)
    -- Now give Class its instance metatable as its own metatable.
    -- Now it can handle method calls.
    setmetatable(class, class.__instance_vars.instance_metatable)
    _G[name] = class
  else
    if not superclass and name ~= "Object" then
      superclass = Object
    end
    _G[name] = Class:new(name, superclass, define_func)
  end
end

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

function dispatch_method(class_self, public_obj, method_name)
  -- This could either be a method call (in which case we want to
  -- return the function for this object's instance method) or it
  -- could be a property access (in which case we want to return
  -- the value of the property itself -- not a function).

  --print(string.format("Dispatching method %s for object of class %s", method_name,
  --      rawget(rawget(public_obj, "__instance_vars").class, "__instance_vars").name))
  local method = find_method(class_self, method_name)
  if method then
    return method
  end

  method = find_method(class_self, "get_" .. method_name)
  if method then
    return method(rawget(public_obj, "__instance_vars"))
  else
    error(string.format("No method or property named '%s'", method_name))
  end
end

function set_property(class_self, public_obj, property_name, value)
  local method = find_method(class_self, "set_" .. property_name)
  if method then
    method(rawget(public_obj, "__instance_vars"), value)
  else
    error(string.format("Can't set property named '%s'", property_name))
  end
end

function find_method(class_self, name)
  local method = class_self.instance_methods[name]
  if not method and class_self.superclass then
    method = find_method(class_self.superclass.__instance_vars, name)
  end
  return method
end


define_class("Class", nil, function(obj, class, class_self)
  -- This is the one class definition ever where obj == class.
  -- Since obj == class == the class "Class", we use the "class"
  -- var here to define everything, so it's less confusing.
  attr_reader(class, "metatable")
  attr_reader(class, "superclass")
  attr_reader(class, "name")

  -- The implementation of Class.new has to create the new object
  -- and call its "initialize" method.
  function class:new(...)
    local new_obj = {}
    new_obj.__instance_vars = {public_obj=new_obj, class=self.public_obj}
    setmetatable(new_obj, self.instance_metatable)
    -- This lets methods call other methods by doing self:foo().
    setmetatable(new_obj.__instance_vars, self.private_instance_metatable)
    new_obj:initialize(...)
    return new_obj
  end

  function class:initialize(name, superclass, define_func)
    -- This method must not call any other methods of Class, because its
    -- method dispatch has not been appropriately initialized yet.
    self.name = name
    self.superclass = superclass

    local obj_methods = {}
    local class_methods = {}
    define_func(obj_methods, class_methods, self)
    obj_methods.initialize = obj_methods.initialize or function() end

    -- Each method needs a wrapper that pulls the private variables out
    -- to pass them to the method.
    self.instance_methods = {}
    for method_name, method_def in pairs(obj_methods) do
      self.instance_methods[method_name] = function(public_obj, ...)
        -- The first is if we were called regularly, the second is if we
        -- were called from within a method (using self:foo()).
        if not public_obj then
          error("Called instance method without passing a receiver " ..
                "(did you forget the colon?)")
        end
        local receiver = rawget(public_obj, "__instance_vars") or public_obj
        if not rawget(receiver, "class") then
          error("Called instance method without passing a receiver " ..
                "(did you forget the colon?)")
        end
        return method_def(receiver, ...)
      end
    end

    for method_name, method_def in pairs(class_methods) do
      rawset(self.public_obj, method_name, function(public_obj, ...)
        -- The first is if we were called regularly, the second is if we
        -- were called from within a method (using self:foo()).
        --print("Dispatching CLASS method for " .. method_name)
        if not public_obj then
          error("Called instance method without passing a receiver " ..
                "(did you forget the colon?)")
        end
        local receiver = rawget(public_obj, "__instance_vars") or public_obj
        if not rawget(receiver, "class") then
          error("Called instance method without passing a receiver " ..
                "(did you forget the colon?)")
        end
        return method_def(receiver, ...)
      end)
    end

    self.instance_metatable = {
      __index = function(public_obj, key)
        return dispatch_method(self, public_obj, key)
      end,
      __newindex = function(public_obj, key, value)
        return set_property(self, public_obj, key, value)
      end
    }
    self.private_instance_metatable = {
      __index = function(obj, key)
        -- To catch undefined variables we'd have to represent "nil" in
        -- the table in a special way, so that we don't error when "nil"
        -- has been explicitly set.
        return find_method(self, key)
      end,
    }
  end

  for k,v in pairs(class) do
    obj[k] = v
  end
end)

define_class("Object", nil, function(obj, class, class_self)
  attr_accessor(obj, "class")
end)

