
function dump_to_html(src_file, grammar, dir)
  os.execute("mkdir -p " .. dir)
  local index = io.open(dir .. "/index.html", "w")
  local title = string.format("Gazelle Grammar Dump: %s", src_file)
  index:write("<!DOCTYPE html>\n")
  index:write("<html>\n")
  index:write(string.format("<head><title>%s</title></head>\n", title))
  index:write("<body>\n")
  index:write("<h1>" .. title .. "</h1>\n")
  index:write("<ul>\n")
  index:write("<li><a href='#rules'>Rules</a></li>\n")
  index:write("<li><a href='#lookahead'>Lookahead</a></li>\n")
  index:write("<li><a href='#lexing'>Lexing</a></li>\n")
  index:write("</ul>")

  index:write("<h2><a name='rules'>Rules</a></h2>\n")
  index:write("<p>The states in the grammar are:</p>")
  local no_gla_breakdown = {}
  local with_gla_breakdown = {}
  local lookaheads = Set:new()
  local total = 0
  for name, rtn in each(grammar.rtns) do
    for state in each(rtn:states()) do
      total = total + 1
      local lookahead
      if state.gla then
        lookahead = state.gla.longest_path
        with_gla_breakdown[lookahead] = with_gla_breakdown[lookahead] or 0
        with_gla_breakdown[lookahead] = with_gla_breakdown[lookahead] + 1
      else
        if state:num_transitions() == 1 then
          lookahead = 0
        else
          lookahead = 1
        end
        no_gla_breakdown[lookahead] = no_gla_breakdown[lookahead] or 0
        no_gla_breakdown[lookahead] = no_gla_breakdown[lookahead] + 1
      end
      lookaheads:add(lookahead)
    end
  end

  lookaheads = lookaheads:to_array()
  table.sort(lookaheads)

  index:write("<ul>")
  for lookahead in each(lookaheads) do
    if no_gla_breakdown[lookahead] then
      index:write(string.format("<li>%0.1f%% LL(%d) (%d/%d states)</li>",
                  no_gla_breakdown[lookahead] / total * 100, lookahead,
                  no_gla_breakdown[lookahead], total))
    end
  end
  for lookahead in each(lookaheads) do
    if with_gla_breakdown[lookahead] then
      local color
      if lookahead == 1 then
        color = "#6495ed"
      elseif lookahead == 2 then
        color = "#ffd700"
      else
        color = "#b22222"
      end
      index:write(string.format("<li>%0.1f%% LL(%d) with GLA (%d/%d states): " ..
                                "indicated with <span style='background-color: %s'>color</span> below</li>",
                  with_gla_breakdown[lookahead] / total * 100, lookahead,
                  with_gla_breakdown[lookahead], total, color))
    end
  end
  index:write("</ul>")

  index:write("<table border='1'>\n")
  for name, rtn in each(grammar.rtns) do
    local rtn_file = io.open(string.format("%s/%s.dot", dir, name), "w")
    rtn_file:write("digraph untitled {\n")
    rtn_file:write(rtn:to_dot("  "))
    rtn_file:write("}\n")
    rtn_file:close()
    os.execute(string.format("dot -Tpng -o %s/%s.png %s/%s.dot", dir, name, dir, name))
    index:write("  <tr>")
    index:write(string.format("  <tr><td rowspan='2'>%s</td><td><pre>%s</pre></td></tr>\n", name, rtn.text))
    index:write(string.format("  <tr><td><img src='%s.png'></td></tr>", name))
  end
  index:write("</table>\n")

  index:write("<h2><a name='lookahead'>Lookahead</a></h2>\n")

  index:write("<h2><a name='lexing'>Lexing</a></h2>\n")
  local intfa_num = 1
  for intfa in each(grammar.master_intfas) do
    local intfa_file = io.open(string.format("%s/intfa-%d.dot", dir, intfa_num), "w")
    intfa_file:write("digraph untitled {\n")
    intfa_file:write("  rankdir=\"LR\"")
    intfa_file:write(intfa:to_dot("  "))
    intfa_file:write("}\n")
    intfa_file:close()
    os.execute(string.format("dot -Tpng -o %s/intfa-%d.png %s/intfa-%d.dot", dir, intfa_num, dir, intfa_num))
    index:write(string.format("<img src='intfa-%d.png'></td></tr>", intfa_num))
    intfa_num = intfa_num + 1
  end

  index:write("</html>\n")
end

