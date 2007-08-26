
require "rtn"

-- First read grammar file

local grm = io.open(arg[1], "r")
local grm_str = grm:read("*a")

grammar, attributes = parse_grammar(CharStream:new(grm_str))

--print(serialize(attributes.ignore))

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

require "sketches/regex_debug"
require "sketches/pp"

Ignore = {name="Ignore"}

-- for nonterm, rtn in pairs(grammar) do
--   print(nonterm)
--   print(rtn)
-- end

-- For each state in the grammar, create (or reuse) a DFA to run
-- when we hit that state.
for nonterm, rtn in pairs(grammar) do
  print(nonterm)
  print(rtn)
  for state in each(rtn:states()) do
    local transition_num = 0
    decisions = {}
    if state:num_transitions() > 0 then
      for edge_val, target_state in state:transitions() do
        transition_num = transition_num + 1
        depth_first_traversal(edge_val, child_edges)
      end

      -- add "ignore" decisions
      if attributes.ignore[nonterm] then
        for ignore in each(attributes.ignore[nonterm]) do
          decisions[ignore] = Ignore
        end
      end

      -- print("Inside " .. nonterm .. ", state=" .. tostring(state) .. "...")
      -- print(serialize(decisions))
      local nfas = {}
      for term, stack in pairs(decisions) do
        local target = attributes.terminals[term]
        if type(target) == "string" then
          target = fa.IntFA:new{string=target}
        end
        table.insert(nfas, {target, term})
      end

      state.dfa = hopcroft_minimize(nfas_to_dfa(nfas))
      state.decisions = decisions
    end
  end
end

chars = regex_parser.TokenStream:new([[{
    "glossary": {
        "title": "example glossary",
                "GlossDiv": {
            "title": "S",
                        "GlossList": {
                "GlossEntry": {
                    "ID": "SGML",
                                        "SortAs": "SGML",
                                        "GlossTerm": "Standard Generalized Markup Language",
                                        "Acronym": "SGML",
                                        "Abbrev": "ISO 8879:1986",
                                        "GlossDef": {
                        "para": "A meta-markup language, used to create markup languages such as DocBook.",
                                                "GlossSeeAlso": ["GML", "XML"]
                    },
                                        "GlossSee": "markup"
                }
            }
        }
    }
}]])

-- parse!
local state_stack = Stack:new()
local nonterm_stack = Stack:new()
nonterm_stack:push(attributes.start)
local state = grammar[attributes.start].start
while state ~= grammar[attributes.start].final or #stack > 0 do
  -- match the next terminal using the current state's DFA
  local dfa = state.dfa
  local dfa_state = dfa.start
  local token = ""

  while chars:lookahead(1) ~= "" do
    local transitions = dfa_state:transitions_for(chars:lookahead(1):byte(), "ANY")
    local transition
    if transitions:count() == 1 then
      for t in each(transitions) do dfa_state = t end
      token = token .. chars:get()
    else
      error("Syntax error when I hit " .. chars:lookahead(1) .. "!")
    end

    if dfa_state.final and dfa_state:transitions_for(chars:lookahead(1):byte(), "ANY"):count() == 0 then
      if dfa_state.final ~= "whitespace" then
        print("\nRecognized token=" .. dfa_state.final .. "  text='" .. token .. "'")
      end
      local action_stack = state.decisions[dfa_state.final]
      -- print("Pre-transition: nonterm_stack="..serialize(nonterm_stack:to_array())..", state="..tostring(state))
      for action in each(action_stack) do
        new_states = state:transitions_for(action, "ANY")
        if new_states:count() == 0 then
          error("This should not happen -- lookahead was calculated incorrectly")
        end

        for s in each(new_states) do state = s end
        if type(action) == "table" and action.class == fa.NonTerm then
          nonterm_stack:push(action.name)
          state_stack:push(state)
          state = grammar[action.name].start
        end

        while state.final do
          print("Recognized an ENTIRE " .. nonterm_stack:top())
          nonterm_stack:pop()
          state = state_stack:pop()
          if #(nonterm_stack:to_array()) == 0 then
            print("Finished parsing!!")
            os.exit()
          end
        end
      end
      --print("Post-transition: nonterm_stack="..serialize(nonterm_stack:to_array())..", state="..tostring(state))
      token = ""
      dfa = state.dfa
      dfa_state = dfa.start
    end
  end
end

