
function dump_to_html(src_file, grammar, dir)
  os.execute("mkdir -p " .. dir)

  local glas = OrderedSet:new()

  for name, rtn in each(grammar.rtns) do
    for state in each(rtn:states()) do
      if state:get_gla() then
        glas:add(state:get_gla())
      end
    end
  end

  local index = io.open(dir .. "/index.html", "w")
  local title = string.format("Gazelle Grammar Dump: %s", src_file)
  index:write("<!DOCTYPE html>\n")
  index:write("<html>\n")
  index:write(string.format("<head><title>%s</title></head>\n", title))
  index:write("<body>\n")
  index:write("<h1>" .. title .. "</h1>\n")
  index:write("<ul>\n")
  index:write("<li><a href='#rules'>Rules</a></li>\n")
  index:write("<ul>\n")
  for name, rtn in each(grammar.rtns) do
    index:write(string.format("<li><a href='#rule_%s'>%s</a></li>", name, name))
  end
  index:write("</ul>\n")
  index:write("<li><a href='#lookahead'>Lookahead</a></li>\n")
  index:write("<ul>\n")
  local gla_num = 1
  for gla in each(glas) do
    index:write(string.format("<li><a href='#gla_%d'>GLA %d</a></li>", gla_num, gla_num))
    gla_num = gla_num + 1
  end
  index:write("</ul>\n")
  index:write("<li><a href='#lexing'>Lexing</a></li>\n")
  index:write("<ul>\n")
  local intfa_num = 1
  for intfa in each(grammar.master_intfas) do
    index:write(string.format("<li><a href='#intfa_%d'>IntFA %d</a></li>", intfa_num, intfa_num))
    intfa_num = intfa_num + 1
  end
  index:write("</ul>\n")
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
      if state:get_gla() then
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
      index:write(string.format("<li>%0.1f%% LL(%d) (%d/%d states)</li>\n",
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
      local lookahead_str
      if lookahead == math.huge then
        lookahead_str = "*"
      else
        lookahead_str = tostring(lookahead)
      end
      index:write(string.format("<li>%0.1f%% LL(%s) with GLA (%d/%d states): \n" ..
                                "indicated with <span style='background-color: %s'>color</span> below</li>\n",
                  with_gla_breakdown[lookahead] / total * 100, lookahead_str,
                  with_gla_breakdown[lookahead], total, color))
    end
  end
  index:write("</ul>")

  index:write("<table border='1'>\n")

  for name, rtn in each(grammar.rtns) do
    local rtn_file = io.open(string.format("%s/%s.dot", dir, name), "w")
    rtn_file:write("digraph untitled {\n")
    rtn_file:write(rtn:to_dot("  ", "", grammar.master_intfas, glas))
    rtn_file:write("}\n")
    rtn_file:close()
    os.execute(string.format("dot -Tpng -o %s/%s.png %s/%s.dot", dir, name, dir, name))
    index:write("  <tr><td rowspan='2'>")
    index:write(string.format("<a name='rule_%s'>%s</td>", name, name))
    index:write(string.format("  <td><pre>%s</pre></td></tr>\n", rtn:get_text()))
    index:write(string.format("  <tr><td><img src='%s.png'></td></tr>\n", name))
  end
  index:write("</table>\n")

  index:write("<h2><a name='lookahead'>Lookahead</a></h2>\n")
  local gla_num = 1
  for gla in each(glas) do
    local dot_file = string.format("%s/gla-%d.dot", dir, gla_num)
    local png_file = string.format("%s/gla-%d.png", dir, gla_num)
    local png_file_no_dir = string.format("gla-%d.png", gla_num)

    local gla_file = io.open(dot_file, "w")
    gla_file:write("digraph untitled {\n")
    gla_file:write("  rankdir=\"LR\";\n")
    gla_file:write(gla:to_dot("  "))
    gla_file:write("}\n")
    gla_file:close()
    os.execute(string.format("dot -Tpng -o %s %s", png_file, dot_file))
    index:write(string.format("<h3><a name='gla_%d'>GLA %d</a></h3>", gla_num, gla_num))
    index:write(string.format("<img src='%s'>", png_file_no_dir))
    index:write("<br>\n")
    gla_num = gla_num + 1
  end

  index:write("<h2><a name='lexing'>Lexing</a></h2>\n")
  index:write(string.format("<p>The grammar's lexer has %d IntFAs, which follow:</p>", grammar.master_intfas:count()))
  local intfa_num = 1
  local have_imagemagick = os.execute("mogrify > /dev/null 2> /dev/null") == 0
  for intfa in each(grammar.master_intfas) do
    local dot_file = string.format("%s/intfa-%d.dot", dir, intfa_num)
    local png_file = string.format("%s/intfa-%d.png", dir, intfa_num)
    local png_file_no_dir = string.format("intfa-%d.png", intfa_num)
    local png_thumb_file = string.format("%s/intfa-%d-thumb.png", dir, intfa_num)
    local png_thumb_file_no_dir = string.format("intfa-%d-thumb.png", intfa_num)

    local intfa_file = io.open(dot_file, "w")
    intfa_file:write("digraph untitled {\n")
    intfa_file:write(intfa:to_dot("  "))
    intfa_file:write("}\n")
    intfa_file:close()
    os.execute(string.format("dot -Tpng -o %s %s", png_file, dot_file))
    local w = 800
    if have_imagemagick then
      local img_info = io.popen(string.format("identify %s", png_file)):read("*a")
      w, h = string.match(img_info, "[^ ]+ [^ ]+ (%d+)x(%d+)")
      w = math.floor(w * 0.7)
      h = math.floor(h * 0.7)
      os.execute(string.format("convert %s -scale %dx%d %s", png_file, w, h, png_thumb_file))
    else
      os.execute(string.format("cp %s %s", png_file, png_thumb_file))
    end
    index:write(string.format("<h3><a name='intfa_%d'>IntFA %d</a></h3>", intfa_num, intfa_num))
    index:write(string.format("<a href='%s'><img style='max-width: %dpx;' src='%s'></a>", png_file_no_dir, w, png_thumb_file_no_dir))
    index:write("<br>\n")
    intfa_num = intfa_num + 1
  end

  index:write("</body>\n")
  index:write("</html>\n")
end

