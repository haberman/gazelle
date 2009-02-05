--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  ll.lua

  Routines for building LL lookahead automata.  We use automata instead
  of tables because lookahead is almost always extremely sparse.  These
  automata are referred to as GLA (Grammar Lookahead Automata), a term
  coined by Terence Parr in his PhD thesis.

  We support calculating LL(*) with the tail recursion capability.  This
  puts us at the same capability as ANTLR, and actually is more powerful
  since ANTLR does not implement the tail recursion capability as of
  this writing.

  Copyright (c) 2008 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

require "fa"


--[[--------------------------------------------------------------------

  compute_lookahead(grammar): Calculates LL(*) lookahead and returns it
  by attaching a .gla member to every nontrivial RTN state in the grammar.

--------------------------------------------------------------------]]--

function compute_lookahead(grammar, k)
  local gla_needing_rtn_states = grammar:get_rtn_states_needing_gla()
  local follow_states = get_follow_states(grammar)
  check_for_nonrecursive_alt(grammar)
  check_for_left_recursion(grammar)

  for state in each(gla_needing_rtn_states) do
    state.gla = construct_gla(state, grammar, follow_states, k)
    state.gla.rtn_state = state
  end
end


--[[--------------------------------------------------------------------

  check_for_nonrecursive_alt(grammar): Checks every rule in the grammar
  to verify that it has at least one path through its RTN that can return
  and not recurse infinitely.  For example, grammars that fail this
  check are:

  a -> a;

  a -> "X" a;  -- note, this grammar is not left-recursive!

  a -> "X" b;
  b -> "X" a;

  Every rule must satisfy this check to be valid, and we must check it
  separately from the rest of lookhead generation, because we will not
  otherwise even attempt to generate lookahead for languages such as:

  a -> a;

  ...and notice that they are complete nonsense as we should.

--------------------------------------------------------------------]]--

function check_for_nonrecursive_alt(grammar)
  local always_recurses = {}

  --[[------------------------------------------------------------------
  As a first step, do a depth-first traversal on each rule to
  answer the question:

    "For rule X, what states must I *always* recurse into,
     regardless of what path I take through the rule?"

   We store the answer to that question for each rule in always_recurses.
  ------------------------------------------------------------------]]--
  for name, rtn in each(grammar.rtns) do
    local all_paths_see
    local found_nonrecursive_alt = false
    local child_states = function(state_tuple)
      local state, seen_nonterms, seen_states = unpack(state_tuple)
      if state.final then
        if all_paths_see then
          all_paths_see = all_paths_see:intersection(seen_nonterms)
        else
          all_paths_see = seen_nonterms:dup()
        end
        return nil
      else
        local dest_states = Set:new()
        local new_seen_states = seen_states:dup()
        new_seen_states:add(state)
        for edge_val, dest_state in state:transitions() do
          if new_seen_states:contains(dest_state) then
            -- skip
          elseif not fa.is_nonterm(edge_val) then
            dest_states:add({dest_state, seen_nonterms, new_seen_states})
          else
            local new_seen = seen_nonterms:dup()
            new_seen:add(edge_val.name)
            dest_states:add({dest_state, new_seen, new_seen_states})
          end
        end
        return dest_states
      end
    end
    depth_first_traversal({rtn.start, Set:new(), Set:new()}, child_states)
    always_recurses[name] = all_paths_see
  end

  -- Now, look for cycles in the graph of what rules *always* call into
  -- each other.  Cycles indicate that there is a cycle of rules that
  -- can never be returned from.  This indicates a bug in the grammar.
  for name, all_paths_see in pairs(always_recurses) do
    local child_recurses = function(rtn_name, stack)
      local children = {}
      for child_rtn_name in each(always_recurses[rtn_name]) do
        if stack:contains(child_rtn_name) then
          error(string.format("Invalid grammar: rule %s had no non-recursive alternative", name))
        end
      end
      return always_recurses[rtn_name]
    end
    depth_first_traversal(name, child_recurses)
  end
end


--[[--------------------------------------------------------------------

  check_for_left_recursion(grammar): Checks all RTNs in the grammar to
  see if they are left recursive.  Errors if so.

--------------------------------------------------------------------]]--

function check_for_left_recursion(grammar)
  for name, rtn in each(grammar.rtns) do
    local states = Set:new()

    local children = function(state, stack)
      local children = {}
      for edge_val, dest_state in state:transitions() do
        if fa.is_nonterm(edge_val) then
          if edge_val.name == name then
            error(string.format("Grammar is not LL(*): it is left-recursive!  Cycle: %s", stack:tostring()))
          end
          table.insert(children, grammar.rtns:get(edge_val.name).start)
        end
      end
      return children
    end

    depth_first_traversal(rtn.start, children)

  end
end


--[[--------------------------------------------------------------------

  get_follow_states(grammar): Calculates what states can directly follow
  each nonterminal in the grammar, and returns it as a map of:
    {rtn_name -> Set of states that directly follow this RTN,
                 anywhere in the grammar}

--------------------------------------------------------------------]]--

function get_follow_states(grammar)
  local follow_states = {}

  -- initialize each set to empty.
  for name, rtn in each(grammar.rtns) do
    follow_states[rtn] = Set:new()
  end

  for name, rtn in each(grammar.rtns) do
    for state in each(rtn:states()) do
      for edge_val, dest_state in state:transitions() do
        if fa.is_nonterm(edge_val) then
          local rtn = grammar.rtns:get(edge_val.name)
          follow_states[rtn]:add(dest_state)
        end
      end
    end
  end

  -- We create a fake state for EOF.  It can follow the grammar's start symbol
  -- and it has only one transition: on EOF, it transitions to a state that
  -- itself has no transitions out of it.
  local eof_state = fa.RTNState:new()
  eof_state:add_transition(fa.eof, fa.RTNState:new())
  eof_state.rtn = {name="eof"}  -- Just need a unique value.
  follow_states[eof_state.rtn] = Set:new()  -- empty, nothing ever follows it.
  follow_states[grammar.rtns:get(grammar.start)]:add(eof_state)

  return follow_states
end


--[[--------------------------------------------------------------------

  class Path: objects represent a path through various RTN states
  of the grammar.  It is used for the NFA-to-DFA construction, because
  we need to track information about the path leading up to each
  NFA state.

--------------------------------------------------------------------]]--

Path = {name="Path"}
function Path:new(rtn_state, predicted_edge, predicted_dest_state)
  local obj = newobject(self)
  obj.history = {}
  obj.lookahead_k = 0
  obj.prediction = {predicted_edge, predicted_dest_state}
  obj.stack = Stack:new()

  obj.original_state = rtn_state
  obj.current_state = rtn_state
  obj.presumed_stack = {}
  obj.seen_sigs = Set:new()
  obj.is_cyclic = false
  obj.is_epsilon_cyclic = false
  obj.epsilon_seen_sigs = Set:new()
  obj.epsilon_seen_follow_states = Set:new()
  return obj
end

function Path:get_abbreviated_history()
  local abbrev = {}
  for hist in each(self.history) do
    table.insert(abbrev, {hist[1], hist[2]})
  end
  return abbrev
end

function Path:enter_rule(rtn, return_to_state, priorities, is_subparser)
  local new_path = self:dup()
  new_path.current_state = rtn.start
  table.insert(new_path.history, {"enter", rtn.name, new_path.current_state, priorities, is_subparser})

  -- Key point: if return_to_state is final and has no outgoing transitions,
  -- then we need not push anything on the stack.  This is the equivalent of a
  -- tail-recursive optimization, but is significant in that it allows us to
  -- calculate lookahead for languages we could not otherwise calculate
  -- lookahead for.
  if return_to_state.final and return_to_state:num_transitions() == 0 then
    -- do nothing.
  else
    new_path.stack:push(return_to_state)
  end

  new_path:check_for_cycles()
  return new_path
end

function Path:return_from_rule(return_to_state, priorities)
  local new_path = self:dup()
  if return_to_state then
    if not new_path.stack:isempty() then error("Must not specify return_to_state!") end
    new_path.current_state = return_to_state
    new_path.epsilon_seen_follow_states:add(return_to_state)
    table.insert(new_path.presumed_stack, return_to_state)
    table.insert(new_path.history, {"return", return_to_state.rtn.name, new_path.current_state, priorities})
  else
    if new_path.stack:isempty() then error("Must specify return_to_state!") end
    new_path.current_state = new_path.stack:pop()
    table.insert(new_path.history, {"return", nil, new_path.current_state, priorities})
  end

  new_path:check_for_cycles()
  return new_path
end

function Path:enter_state(term, state, priorities)
  local new_path = self:dup()
  new_path.current_state = state
  new_path.lookahead_k = new_path.lookahead_k + 1
  table.insert(new_path.history, {"term", term, state, priorities})

  -- Clear everything concerned with epsilon transitions.
  new_path.epsilon_seen_sigs = Set:new()
  new_path.epsilon_seen_follow_states = Set:new()

  new_path:check_for_cycles()
  return new_path
end

function Path:signature(include_prediction)
  local sig = self.stack:to_array()
  table.insert(sig, self.current_state)
  if include_prediction then
    table.insert(sig, self.prediction)
  end
  sig = get_unique_table_for(sig)
  return sig
end

function Path:check_for_cycles()
  if self.seen_sigs:contains(self:signature()) then
    self.is_cyclic = true
  end
  if self.epsilon_seen_sigs:contains(self:signature()) then
    self.is_epsilon_cyclic = true
  end
  self.seen_sigs:add(self:signature())
  self.epsilon_seen_sigs:add(self:signature())
end

function Path:check_for_epsilon_cycles()
  if self.seen_sigs:contains(self:signature()) then
    self.is_cyclic = true
  end
  self.seen_sigs:add(self:signature())
end

function Path:is_regular()
  local seen_states = Set:new()
  for return_to_state in each(self.stack) do
    if seen_states:contains(return_to_state) then
      return false
    end
    seen_states:add(return_to_state)
  end
  return true
end

function Path:dup()
  local new_path = newobject(Path)
  new_path.history = table_shallow_copy(self.history)
  new_path.lookahead_k = self.lookahead_k
  new_path.prediction = self.prediction
  new_path.stack = self.stack:dup()

  new_path.original_state = self.original_state
  new_path.current_state = self.current_state
  new_path.presumed_stack = table_shallow_copy(self.presumed_stack)
  new_path.seen_sigs = self.seen_sigs:dup()
  new_path.is_cyclic = self.is_cyclic
  new_path.is_epsilon_cyclic = self.is_epsilon_cyclic
  new_path.epsilon_seen_sigs = self.epsilon_seen_sigs:dup()
  new_path.epsilon_seen_follow_states = self.epsilon_seen_follow_states:dup()

  return new_path
end


--[[--------------------------------------------------------------------

  construct_gla(state, grammar, follow_states): Creates a GLA for the
  given state, using a special-purpose NFA-to-DFA construction.  This
  algorithm is largely based on ANTLR's LL(*) lookahead algorithm.

--------------------------------------------------------------------]]--

function construct_gla(state, grammar, follow_states, k)
  -- Each GLA state tracks the set of cumulative RTN paths that are
  -- represented by this state.  To bootstrap the process, we take
  -- each path to and past its first terminal.
  local gla = fa.GLA:new()
  local initial_term_transitions = {}
  local noterm_paths = Set:new()  -- paths that did not consume their first terminal
  local prediction_languages = {}

  for edge_val, dest_state, properties in state:transitions() do
    local path = Path:new(state, edge_val, dest_state)
    if fa.is_nonterm(edge_val) then
      noterm_paths:add(path:enter_rule(grammar.rtns:get(edge_val.name), dest_state, properties.priorities, properties.slotnum == -1))
    else
      initial_term_transitions[edge_val] = initial_term_transitions[edge_val] or Set:new()
      initial_term_transitions[edge_val]:add(path:enter_state(edge_val, dest_state, properties.priorities))
    end
  end

  -- For final states we also have to be able to predict when they should return.
  if state.final then
    local path = Path:new(state, 0, 0)
    for follow_state in each(follow_states[state.rtn]) do
      noterm_paths:add(path:return_from_rule(follow_state, state.final.priorities))
    end
  end

  -- Take each path to and through its first terminal transition
  for path in each(noterm_paths) do
    local paths = get_rtn_state_closure({path}, grammar, follow_states)
    for term in each(get_outgoing_term_edges(paths)) do
      for one_term_path in each(get_dest_states(paths, term)) do
        initial_term_transitions[term] = initial_term_transitions[term] or Set:new()
        initial_term_transitions[term]:add(one_term_path)
      end
    end
  end

  local queue = Queue:new()
  local gla_states = {}

  for term, paths in pairs(initial_term_transitions) do
    local new_gla_state = fa.GLAState:new(paths)
    for path in each(paths) do
      -- Initialize all prediction languages to "fixed" (which is what they are
      -- until demonstrated otherwise).
      prediction_languages[path.prediction] = "fixed"
    end
    gla.start:add_transition(term, new_gla_state)
    gla_states[paths:hash_key()] = new_gla_state
    queue:enqueue(new_gla_state)
  end

  while not queue:isempty() do
    local gla_state = queue:dequeue()

    if k then
      if gla_state.lookahead_k > k then
        error("Grammar is not LL(k) for user-specified k=" .. k)
      end
    else
      check_for_termination_heuristic(gla_state, prediction_languages)
    end

    check_for_ambiguity(gla_state)

    local alt = get_unique_predicted_alternative(gla_state.rtn_paths)
    if alt then
      -- this DFA path has uniquely predicted an alternative -- set the
      -- state final and stop exploring this path
      gla_state.final = alt
    else
      -- this path is still ambiguous about what rtn transition to take --
      -- explore it further
      local paths = get_rtn_state_closure(gla_state.rtn_paths, grammar, follow_states)

      for edge_val in each(get_outgoing_term_edges(paths)) do
        local paths = get_dest_states(paths, edge_val)

        local maybe_new_gla_state
        local hash_key = paths:hash_key()
        if gla_states[hash_key] then
          maybe_new_gla_state = gla_states[hash_key]
        else
          maybe_new_gla_state = fa.GLAState:new(paths)
          gla_states[hash_key] = maybe_new_gla_state
          queue:enqueue(maybe_new_gla_state)
        end
        gla_state:add_transition(edge_val, maybe_new_gla_state)
      end
    end
  end

  gla = hopcroft_minimize(gla)
  for state in each(gla:states()) do
    state.gla = gla
  end
  remove_excess_states(gla)
  gla.longest_path = fa_longest_path(gla)

  -- Check for predictions that have no final state indicating them.  These
  -- indicate alternatives that will never be taken.
  local untaken_predictions = Set:new()
  for prediction, _ in pairs(prediction_languages) do
    untaken_predictions:add(prediction)
  end
  for state in each(gla:states()) do
    if state.final then
      untaken_predictions:remove(state.final)
    end
  end

  if untaken_predictions:count() > 0 then
    -- In the grammar s -> "X" / "X"; the second prioritized choice will never be taken.
    -- This is an error in the grammar, because it means the second option is redundant.
    error("Error in grammar: transition in " .. state.rtn.name .. " will never be taken.")
  end

  return gla
end

--[[--------------------------------------------------------------------

  remove_excess_states(gla): Given a minimized GLA, find states that
  can be removed because a previous state already has enough
  information to predict an alternative.  This can happen when
  a user has used ambiguity resolution, which removed a path that
  would have otherwise been ambiguous.  The path has already been
  traced all the way to the ambiguous state, but with the lower-priority
  path removed, the decision might be possible to make in fewer
  transitions.

--------------------------------------------------------------------]]--

function remove_excess_states(gla)
  for state in each(gla:states()) do
    local seen_alts = Set:new()
    local child_states = function(state)
      if state.final then
        seen_alts:add(state.final)
      end
      local dest_states = {}
      for edge_val, dest_state in state:transitions() do
        table.insert(dest_states, dest_state)
      end
      return dest_states
    end
    depth_first_traversal(state, child_states)
    if seen_alts:count() == 0 then
      error("Unexpected -- please report this stack trace and the input grammar!")
    elseif seen_alts:count() == 1 then
      state.final = seen_alts:sample()
      state:clear_transitions()
    end
  end
end

--[[--------------------------------------------------------------------

  get_lower_priority_paths(paths): Given a set of paths that have
  already been discovered to be ambiguous, for any that diverged
  at a point where the user specified prioritized choice, return the
  path(s) that took the lower-priority choice.

  This is a heinous n^2 algorithm right now -- I'm pretty sure it
  could be made cheaper than that.

--------------------------------------------------------------------]]--

function get_lower_priority_paths(paths)
  local presumed_stacks = {}
  for path in each(paths) do
    table.insert(presumed_stacks, path.presumed_stack)
  end
  local paths_to_remove = Set:new()
  for path1 in each(paths) do
    for path2 in each(paths) do
      if path1 ~= path2 then
        -- find the state where the paths diverge
        local i = 0
        while true do
          i = i + 1
          if path1.history[i] == nil or path2.history[i] == nil then break end
          local _, _, dest_state1, priorities1 = unpack(path1.history[i])
          local _, _, dest_state2, priorities2 = unpack(path2.history[i])
          if priorities1 ~= priorities2 then
            if priorities1 and priorities2 then
              for priority_class, priority1 in pairs(priorities1) do
                local priority2 = priorities2[priority_class]
                if priority2 then
                  if priority1 > priority2 then
                    paths_to_remove:add(path2)
                  elseif priority2 > priority1 then
                    paths_to_remove:add(path1)
                  end
                end
              end
            end
            break
          end
        end
      end
    end
  end

  for path in each(paths_to_remove) do
    paths:remove(path)
  end

  local common_prefix_len = get_common_prefix_len(presumed_stacks)

  if paths:count() == 1 then
    -- If the only remaining path(s) have presumed stacks, then we can't
    -- build a proper GLA for this RTN state.
    if #paths:sample().presumed_stack > common_prefix_len then
      error("Gazelle cannot support this resolution of the ambiguity in rule " .. paths:sample().original_state.rtn.name)
    end
  end

  return paths_to_remove
end


--[[--------------------------------------------------------------------

  get_subparser_redundant_paths(paths): Given a set of paths that have
  already been discovered to be ambiguous, for any that differ only by
  where the call to the subparser happens, return all but one path
  (the one that takes the subparser earliest).

--------------------------------------------------------------------]]--

function get_subparser_redundant_paths(paths)
  -- First question: are any of the paths identical except for where they
  -- put the subparser?  To determine this, create copies of all paths with
  -- subparser calls removed.
  local no_subparser_paths = {}
  for path in each(paths) do
    local no_subparser_history = {}
    local subparser_depth = 0
    for history in each(path.history) do
      if subparser_depth > 0 then
        if history[1] == "return" then
          subparser_depth = subparser_depth - 1
        elseif history[1] == "enter" then
          subparser_depth = subparser_depth + 1
        end
      elseif history[1] == "enter" and history[5] == true then
        subparser_depth = 1
      else
        table.insert(no_subparser_history, get_unique_table_for(history))
      end
    end
    -- history_key uniquely identifies a particular path with all subparser
    -- calls removed.
    local history_key = get_unique_table_for(no_subparser_history)
    no_subparser_paths[history_key] = no_subparser_paths[history_key] or Set:new()
    no_subparser_paths[history_key]:add(path)
  end

  -- Now, for any paths that only differ by placement of the subparser,
  -- create a list of all but the one that puts the subparser the earliest.
  -- TODO: we don't currently support resolving ambiguity between
  -- multiple subparsers, or between regular components and subparsers.
  -- And we probably never will (it's very unlikely to actually be what
  -- was intended), but the error messages around this could be improved.
  local redundant_paths = {}
  for history_key, paths in pairs(no_subparser_paths) do
    if paths:count() > 1 then
      local offset = 1
      local has_subparser_paths = Set:new()
      local winning_path = nil
      local reached_end = false
      while reached_end == false do
        reached_end = true
        for path in each(paths) do
          if path.history[offset] then
            reached_end = false
            if path.history[offset][5] == true then
              -- This path has a subparser call somewhere.
              has_subparser_paths:add(path)
              if not winning_path then
                -- This path has the subparser first and therefore wins.
                winning_path = path
              end
            end
          end
        end
        offset = offset + 1
      end

      -- Create a list of all but the winning path.
      if winning_path then
        if has_subparser_paths:count() < paths:count() then
          error("What you have done is weird: you have a subparser (@allow) " ..
                "competing with a regular rule component.  This is probably not " ..
                "what you meant to do.")
        end
        for path in each(paths) do
          if path ~= winning_path then
            table.insert(redundant_paths, path)
          end
        end
      end

    end
  end

  return redundant_paths
end

--[[--------------------------------------------------------------------

  check_for_ambiguity(gla_state): If for any series of terminals
  (which is what this GLA state represents) we have more than one
  RTN path that is in the same state, *and* both have the same
  stack, we have found an ambiguity.

  Example grammars that can trigger this check:

    s -> "X" | "X";

    s -> a | b;
    a -> b;
    b -> "X";

--------------------------------------------------------------------]]--


function check_for_ambiguity(gla_state)
  local signatures = {}

  for path in each(gla_state.rtn_paths) do
    local signature = path:signature()
    signatures[signature] = signatures[signature] or Set:new()
    signatures[signature]:add(path)
  end

  for signature, paths in pairs(signatures) do
    if paths:count() > 1 then
      -- If one path is prioritized higher than the others by explicit ambiguity
      -- resolution, remove all other (lower-priority) paths.
      local lower_priority_paths = get_lower_priority_paths(paths)
      for path in each(lower_priority_paths) do
        gla_state.rtn_paths:remove(path)
      end

      -- Subparsers (whitespace ignoring) create real ambiguity because there
      -- are often cases where the whitespace could be attached to any number
      -- of places in the parse tree.  In these cases we choose whatever path
      -- attaches the subparser to the higest part of the tree -- whatever path
      -- processes the whitespace/subparser earliest.
      local subparser_redundant_paths = get_subparser_redundant_paths(paths)
      for path in each(subparser_redundant_paths) do
        gla_state.rtn_paths:remove(path)
        paths:remove(path)
      end
    end

    if not get_unique_predicted_alternative(paths) then
      -- We know at this point that we cannot support this grammar.
      -- However we do a little bit more detective work to understand
      -- why this is, as best as we can, to give a good message to the user.

      local common_k = math.huge
      local presumed_stacks = {}
      for path in each(paths) do
        local stack = get_unique_table_for(path.presumed_stack)
        presumed_stacks[stack] = presumed_stacks[stack] or Set:new()
        presumed_stacks[stack]:add(path)

        common_k = math.min(common_k, #path.presumed_stack)
      end

      for _, same_stack_paths in pairs(presumed_stacks) do
        if same_stack_paths:count() > 1 then
          local path
          for p in each(same_stack_paths) do
            path = p
          end
          local err = "Ambiguous grammar for state starting in rule " ..
                      path.original_state.rtn.name .. ", paths="
          local first = true
          for path in each(same_stack_paths) do
            if first then
              first = false
            else
              err = err .. " AND "
            end
            err = err .. serialize(path:get_abbreviated_history())
          end
          error(err)
        end
      end

      local common_stacks = {}
      for path in each(paths) do
        local stack = get_unique_table_for(clamp_table(path.presumed_stack, common_k))
        if common_stacks[stack] then
          error("Gazelle cannot handle this grammar.  It is not Strong-LL or full-LL (and may be ambiguous, but we don't know).")
        end
        common_stacks[stack] = true
      end

      -- TODO: find a grammar that exercises this case.
      error("This grammar is full-LL but not strong-LL")
    end
  end
end


--[[--------------------------------------------------------------------

  check_for_termination_heuristic(gla_state, prediction_languages): Check
  to see if the grammar fails a heuristic that detects most non-LL(*)
  grammars.  It will have some false positives (deciding that a grammar
  is not LL(*) when in fact it is), but I am convinced that most real-world
  grammars will not fall into this case.  For false positives, the user
  can always opt to specify an explicit 'k' value for LL(k), which will
  prevent Gazelle from using this heuristic and always extend the search
  at least 'k' terminals.

  The heursitic is based on the fact that we *know* we can generate
  correct lookahead if the grammar falls into one of two cases:

  - all alternatives have regular lookahead languages.  In this case
    we build a GLA which is guaranteed to be regular because it is the
    combination of a bunch of regular languages.
  - at most one alternative has a nonregular lookahead language.  In
    this case all of the other alternatives must have LL(k) (LL(*)
    won't do) lookahead languages.  This works because once we have
    determined k for the other alternatives, we can enumerate all
    strings of terminals <= length k in the nonregular language,
    and combine them with the other LL(k) lookahead.

  So to detect if we are dealing with a language we can't parse, we
  need to do the following check:

  if any of the alternatives have nonregular lookahead
    if any of the *other* alternatives are cyclic or nonregular
      return failure

--------------------------------------------------------------------]]--

function check_for_termination_heuristic(gla_state, prediction_languages)
  -- First remove all lower-priority paths in cases where ambiguity resolution
  -- was used, so that we don't trigger the heuristic for paths that are being
  -- explicitly prioritized.
  local non_prioritized_paths = gla_state.rtn_paths:dup()
  for path in each(get_lower_priority_paths(non_prioritized_paths)) do
    non_prioritized_paths:remove(path)
  end

  for path in each(non_prioritized_paths) do
    if not path:is_regular() then
      prediction_languages[path.prediction] = "nonregular"
    end

    if path.is_cyclic and prediction_languages[path.prediction] ~= "nonregular" then
      prediction_languages[path.prediction] = "cyclic"
    end
  end

  for prediction, language in pairs(prediction_languages) do
    if language == "nonregular" then
      for prediction2, language2 in pairs(prediction_languages) do
        if prediction ~= prediction2 and language2 ~= "fixed" then
          -- TODO: more info about which languages they were.
          error("Language is probably not LL(k) or LL(*): when calculating lookahead for a state in " .. gla_state.rtn_paths:to_array()[1].prediction[2].rtn.name .. ", one lookahead language was nonregular, others were not all fixed")
        end
      end
    end
  end
end


--[[--------------------------------------------------------------------

  get_unique_predicted_alternative(gla_state): If all the RTN paths
  that arrive at this GLA state predict the same alternative, return
  it.  Otherwise return nil.

--------------------------------------------------------------------]]--

function get_unique_predicted_alternative(rtn_paths)
  local first_prediction = rtn_paths:to_array()[1].prediction

  for path in each(rtn_paths) do
    if path.prediction ~= first_prediction then
      return nil
    end
  end

  return first_prediction
end


--[[--------------------------------------------------------------------

  get_outgoing_term_edges(rtn_paths): Get a set of terminals that
  represent outgoing transitions from this set of RTN states.  This
  represents the set of terminals that will lead out of this GLA
  state.

--------------------------------------------------------------------]]--

function get_outgoing_term_edges(rtn_paths)
  local edges = Set:new()

  for path in each(rtn_paths) do
    for edge_val in path.current_state:transitions() do
      if not fa.is_nonterm(edge_val) then
        edges:add(edge_val)
      end
    end
  end

  return edges
end


--[[--------------------------------------------------------------------

  get_dest_states(rtn_paths, edge_val): Given the set of RTN states
  we are currently in, and a terminal transition value, return the
  list of RTN states we will be in after transitioning on this terminal.

--------------------------------------------------------------------]]--

function get_dest_states(rtn_paths, edge_val)
  local dest_states = Set:new()

  for path in each(rtn_paths) do
    for dest_state_properties in each(path.current_state:transitions_for(edge_val, "ANY")) do
      local dest_state, properties = unpack(dest_state_properties)
      local priorities
      if properties then
        priorities = properties.priorities
      else
        priorities = get_unique_table_for({})
      end
      dest_states:add(path:enter_state(edge_val, dest_state, priorities))
    end
  end

  return dest_states
end


--[[--------------------------------------------------------------------

  get_rtn_state_closure(dest_states, follow_states): Given the set of
  states we are currently in, return the list of states we could
  possibly reach without seeing a terminal (the equivalent of epsilon
  transitions).  The two epsilon transitions of this sort are
  returning from a final state and descending into a sub-rule.

--------------------------------------------------------------------]]--

-- This method is a helper method for the depth-first search of
-- get_rtn_state_closure.
function get_rtn_state_closure_for_path(path, grammar, follow_states)
  local child_epsilon_paths = function(path)
    local child_paths = {}
    if path.current_state.transitions == nil then
      print(serialize(path.current_state, 4, "  "))
    end
    for edge_val, dest_state, properties in path.current_state:transitions() do
      if fa.is_nonterm(edge_val) then
        local dest_rtn = grammar.rtns:get(edge_val.name)
        local new_path = path:enter_rule(dest_rtn, dest_state, properties.priorities, properties.slotnum==-1)
        if new_path.is_epsilon_cyclic then
          error("Ambiguous grammar -- it has cycles in its epsilon transitions!")
        end
        table.insert(child_paths, new_path)
      end
    end

    if path.current_state.final then
      if not path.stack:isempty() then
        -- The stack has context that determines what state we should return to.
        table.insert(child_paths, path:return_from_rule(nil, path.current_state.final.priorities))
      else
        -- There is no context -- we could be in any state that follows this state
        -- anywhere in the grammar.
        local follow_base
        if #path.presumed_stack > 0 then
          follow_base = path.presumed_stack[#path.presumed_stack]
        else
          follow_base = path.original_state
        end
        for state in each(follow_states[follow_base.rtn]) do
          if not path.epsilon_seen_follow_states:contains(state) then
            table.insert(child_paths, path:return_from_rule(state, path.current_state.final.priorities))
          end
        end
      end
    end
    return child_paths
  end

  return depth_first_traversal(path, child_epsilon_paths)
end

function get_rtn_state_closure(paths, grammar, follow_states)
  local closure = Set:new()
  for path in each(paths) do
    closure:add_collection(get_rtn_state_closure_for_path(path, grammar, follow_states))
  end
  return closure
end

-- vim:et:sts=2:sw=2
