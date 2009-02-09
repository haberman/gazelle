--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  nfa_construct.lua

  Construct NFAs based on primitives of concatenation, alternation,
  and repetition/kleene-star.  The construction is as given in
  "Programming Language Pragmatics," by Michael L. Scott (see
  BIBLIOGRAPHY for more info).

  Copyright (c) 2007 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

require "fa"

module("nfa_construct", package.seeall)

--[[--------------------------------------------------------------------

  concat(nfa1, nfa2): Returns a concatenations of two NFAs.
  eg. for the NFAs A and B:

     A
  o ---> *
                             A      e      B
     B       ...becomes:  o ---> o ---> o ---> *
  o ---> *

--------------------------------------------------------------------]]--

function concat(nfa1, nfa2)
  nfa1:get_final():add_transition(fa.e, nfa2:get_start())
  return nfa1:get_class():new{start = nfa1:get_start(), final = nfa2:get_final()}
end


--[[--------------------------------------------------------------------

   alt([nfa1, nfa2, ...]): Returns an alternation of the given NFAs.
   eg. for the NFAs A, B, and C:

        A                      e      A      e
     o ---> *               ,----> o ---> o -----,
                            |                    |
        B                   |  e      B      e   v
     o ---> *  ...becomes:  o ---> o ---> o ---> *
                            |                    ^
        C                   |  e      C      e   |
     o ---> *               +----> o ---> o -----'

--------------------------------------------------------------------]]--

function alt(nfas, prioritized)
  local new_nfa = nfas[1]:get_class():new()
  local priority_class = {}

  for i=1,#nfas do
    local properties
    if prioritized then
      properties = {
        priority_class = priority_class,
        priority = #nfas - i + 1  -- priorities count down from #nfas to 0
      }
    end

    new_nfa:get_start():add_transition(fa.e, nfas[i]:get_start(), properties)
    nfas[i]:get_final():add_transition(fa.e, new_nfa:get_final())
  end

  return new_nfa
end

-- alt2(nfa1, nfa2): a convenience wrapper for alternation of 2 NFAs.
function alt2(nfa1, nfa2, prioritized)
  return alt({nfa1, nfa2}, prioritized)
end

function get_repeating_properties(favor_repeating)
  local repeat_properties
  local finish_properties

  if favor_repeating ~= nil then
    local priority_class = {}  -- just a unique value
    repeat_properties = {priority_class=priority_class}
    finish_properties = {priority_class=priority_class}
    if favor_repeating then
      repeat_properties.priority = 2
      finish_properties.priority = 1
    else
      repeat_properties.priority = 1
      finish_properties.priority = 2
    end
  end

  return repeat_properties, finish_properties
end

--[[--------------------------------------------------------------------

  rep(nfa): Returns the given NFA repeated one or more times.
  eg. for the NFA A:


     A                      e      A      e
  o ---> *  ...becomes:  o ---> o ---> o ---> *
                                ^      |
                                +------+
                                   e

  Note: This construction isn't strictly necessary: we could always
  rewrite A+ as AA*, therefore using the kleene star to construct
  all repetition.  However, this makes for less understandable NFAs.
  The difference would disappear in the minimization state, but it's
  nice to keep the FAs as understandable as possible at every stage.

--------------------------------------------------------------------]]--

function rep(nfa, favor_repeat)
  local new_nfa = nfa:get_class():new()
  local repeat_properties, finish_properties = get_repeating_properties(favor_repeating)
  new_nfa:get_start():add_transition(fa.e, nfa:get_start())
  nfa:get_final():add_transition(fa.e, nfa:get_start(), repeat_properties)
  nfa:get_final():add_transition(fa.e, new_nfa:get_final(), finish_properties)
  return new_nfa
end


--[[--------------------------------------------------------------------

  kleene(nfa): Returns the given NFA repeated zero or more times.
  eg. for the regular expression A*  :

                                      e
                            +--------------------+
                            |                    |
        A                   |  e      A      e   v
     o ---> *  ...becomes:  o ---> o ---> o ---> *
                                   ^      |
                                   +------+
                                      e

--------------------------------------------------------------------]]--

function kleene(nfa, favor_repeat)
  local new_nfa = rep(nfa)
  local repeat_properties, finish_properties = get_repeating_properties(favor_repeat)
  new_nfa:get_start():add_transition(fa.e, nfa:get_start())
  new_nfa:get_start():add_transition(fa.e, new_nfa:get_final(), finish_properties)
  nfa:get_final():add_transition(fa.e, nfa:get_start(), repeat_properties)
  nfa:get_final():add_transition(fa.e, new_nfa:get_final(), finish_properties)
  return new_nfa
end

-- vim:et:sts=2:sw=2
