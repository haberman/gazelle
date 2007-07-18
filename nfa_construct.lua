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
  nfa1.final:add_transition(fa.e, nfa2.start)
  return nfa1:new_graph{start = nfa1.start, final = nfa2.final}
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
  local new_nfa = nfas[1]:new_graph()

  for i=1,#nfas do
    new_nfa.start:add_transition(fa.e, nfas[i].start)
    nfas[i].final:add_transition(fa.e, new_nfa.final)
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
  local new_nfa = nfa:new_graph()
  new_nfa.start:add_transition(fa.e, nfa.start)
  nfa.final:add_transition(fa.e, nfa.start)
  nfa.final:add_transition(fa.e, new_nfa.final)
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
  new_nfa.start:add_transition(fa.e, nfa.start)
  new_nfa.start:add_transition(fa.e, new_nfa.final)
  nfa.final:add_transition(fa.e, nfa.start)
  nfa.final:add_transition(fa.e, new_nfa.final)
  return new_nfa
end

