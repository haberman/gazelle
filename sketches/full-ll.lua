--[[--------------------------------------------------------------------

Editor's note: at one point I was toying around with this code that,
when checking for ambiguity in compiler/ll.lua, would be able to detect
cases that were full-LL but not strong-LL.  But things got really
complicated really fast, and since I don't actually care about
full-LL at the moment, I ripped this code out.  Here it lies.

--------------------------------------------------------------------]]--

function Path:return_stack(max)
  local stack = {}
  for action_arg_pair in each(self.path) do
    local action, arg = unpack(action_arg_pair)
    if action == "return" and arg then
      if not max or #stack < max then
        table.insert(stack, arg)
      end
    end
  end
  return stack
end


-- The following code was in check_for_ambiguity
      -- If all paths involved "returns" from rules where no stack context was
      -- available (meaning we had to use follow states), and k is the minimum
      -- number of such returns that all stacks have done, then the rules to
      -- which all paths have "returned" for their first k returns must be
      -- identical for the paths to be considered ambiguous.  Because otherwise
      -- the paths are not ambiguous -- they would be distinguished by their
      -- contexts.
      --
      -- If this is the case (their first k returns differ) and the two paths
      -- predict the same alternative, we are fine -- building the GLA continues.
      -- But if they predict *different* alternatives, this indicates that the
      -- grammar is full-LL and not strong-LL.

      local min_k = math.huge
      local all_same_k = true
      local return_stacks = Set:new()
      for state_path in each(rtn_states[signature]) do
        if min_k ~= math.huge and min_k ~= #state_path:return_stack() then
          all_same_k = false
        end
        min_k = math.min(min_k, #state_path:return_stack())
      end

      -- Note that the next loop will trivially fail if min_k == 0 (ie. none of
      -- this "return stack" funny business going on at all -- a signature clash
      -- is a signature clash, which indicates an ambiguity), as a special case
      -- of solving the more general problem.
      local k_length_return_stacks = {}
      for state_path in each(rtn_states[signature]) do
        local unique_return_path = get_unique_table_for(state_path:return_stack(min_k))
        if k_length_return_stacks[unique_return_path] then
          local err
          if all_same_k then
            -- This is the one case where we can truly detect that the path was
            -- a true ambiguity in the grammar.
            err = "Ambiguous grammar for paths " .. serialize(state_path.path) ..
                  " and " .. serialize(k_length_return_stacks[unique_return_path].path)
            error(err)
          else
            if not get_unique_predicted_alternative(rtn_states[signature]) then
              -- This grammar is definitely not Strong-LL(k), and is *probably not
              -- full-LL(k) either (but don't quote me on that).
              err = "Gazelle cannot handle this grammar -- it is not Strong-LL(k). " ..
                    "The problem is that when generating lookahead for state %d in rule " ..
                    "%s, there were two paths through the grammar that consumed the same " ..
                    "series of terminals and ended in the same state, but predicted different " ..
                    "alternatives.  This could be an ambiguity in the grammar, " ..
                    "or it could just be a non-ambiguous language that lies outside LL.  " ..
                    "The paths are: " .. serialize(state_path.path) ..
                    " and " .. serialize(k_length_return_stacks[unique_return_path].path)
              error(err)
            end
          end
        end
        k_length_return_stacks[unique_return_path] = state_path
      end

      -- Well if we got here it means that the paths weren't truly ambiguous
      -- (their return stacks differed), but we're not out of the woods yet.
      -- We have to ensure that they all predict the same alternative, or else
      -- this grammar is full-LL but not strong-LL.
      if not get_unique_predicted_alternative(rtn_states[signature]) then
        error("Gazelle cannot handle this grammar: it is full-LL but not strong-LL")
      end
    else
      rtn_states[signature] = Set:new()
      rtn_states[signature]:add(path)
    end

-- the following code was in get_follow_states_and_paths
  -- Now turn the flat list of follow states into follow *paths*, by depth-first
  -- searching the paths of follow states, bounding the search when we find cycles.
  -- We only add states with a terminal transition out of them, and for each such
  -- state we also include the return stack of such a path.
  local follow_paths = {}
  for name, rtn in each(grammar.rtns) do
    follow_paths[rtn] = {}

    function children_func(state, stack)
      if stack:count() > 1 and state:has_terminal_transition() then
        local stack_array = stack:to_array()
        table.remove(stack_array, 1) -- don't care about the fake state at the bottom
        table.insert(follow_paths[rtn], stack_array)
      end

      local children = {}
      if state.final then
        for follow_state in each(follow_states[state.rtn]) do
          if not stack:contains(follow_state) then
            table.insert(children, follow_state)
          end
        end
      end
      return children
    end

    -- seed with a fake state that is final and has this rtn
    depth_first_traversal({final=true, rtn=rtn}, children_func, true)
  end

