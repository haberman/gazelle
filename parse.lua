
require "rtn"

-- First read grammar file

local grm = io.open(arg[1], "r")
local grm_str = grm:read("*a")

grammar = parse_grammar(CharStream:new(grm_str))

function child_edges(edge, stack)
  if type(edge) == "table" and edge.class == fa.NonTerm then
    local child_edges = {}
    for edge_val in grammar[edge.name].start:transitions() do
      table.insert(child_edges, edge_val)
    end
    return child_edges
  else
    local str_or_regex
    if type(edge) == "table" then
      str_or_regex = edge.properties.string
    else
      str_or_regex = edge
    end

    decisions[str_or_regex] = stack:to_array()
  end
end

-- For each state in the grammar, create (or reuse) a DFA to run
-- when we hit that state.
for nonterm, rtn in pairs(grammar) do
  for state in each(rtn:states()) do
    local transition_num = 0
    decisions = {}
    for edge_val, target_state in state:transitions() do
      transition_num = transition_num + 1
      terminals = depth_first_traversal(edge_val, child_edges)
    end
    print(serialize(decisions))
  end
end

