--[[--------------------------------------------------------------------

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
  nfa1.final.transitions["e"] = {nfa2.start}
  return FA:new{start = nfa1.start, final = nfa2.final}
end


--[[--------------------------------------------------------------------

  capture(nfa): Creates capturing transitions around an NFA.
  eg. for the NFA A:

     A                       (      A      )
  o ---> *   ...becomes:  o ---> o ---> o ---> o

  ...where '(' is 'begin capture' and ')' is 'end capture.'

--------------------------------------------------------------------]]--

function capture(nfa)
  local new_nfa = FA:new()
  new_nfa.start.transitions["("], nfa.final.transitions[")"] = {nfa.start}, {new_nfa.final}
  return new_nfa
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

function alt(nfas)
  local new_nfa = FA:new()
  new_nfa.start.transitions["e"] = {}

  for i=1,#nfas do
    table.insert(new_nfa.start.transitions["e"], nfas[i].start)
    nfas[i].final.transitions["e"] = {new_nfa.final}
  end

  return new_nfa
end

-- alt2(nfa1, nfa2): a convenience wrapper for alternation of 2 NFAs.
function alt2(nfa1, nfa2)
  return alt({nfa1, nfa2})
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

function rep(nfa)
  local new_nfa = FA:new()
  new_nfa.start.transitions["e"] = {nfa.start}
  nfa.final.transitions["e"] = {nfa.start, new_nfa.final}
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

function kleene(nfa)
  local new_nfa = rep(nfa)
  new_nfa.start.transitions["e"] = {nfa.start, new_nfa.final}
  nfa.final.transitions["e"] = {nfa.start, new_nfa.final}
  return new_nfa
end


--[[--------------------------------------------------------------------

  char(char): Returns the NFA that matches a single symbol.
  eg. for the regular expression A, constructs:

       A
    o ---> *

  Note: 'char' might be something more complicated, like an IntSet.

--------------------------------------------------------------------]]--

function char(char)
  local new_nfa = FA:new()
  new_nfa.start.transitions[char] = {new_nfa.final}
  return new_nfa
end

function epsilon()
  return char("e")
end

