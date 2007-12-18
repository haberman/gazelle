
require "pp"
require "bootstrap/rtn"

-- http://www.engr.mun.ca/~theo/Misc/exp_parsing.htm

function get_primary(text)
  if text:match("%(") then
    text:consume_pattern("%(")
    local prim = parse(text)
    text:consume_pattern("%)")
    return prim
  elseif text:match("%d") then
    return text:consume_pattern("%d")
  else
    return nil
  end
end

Binary = {}
Unary = {}

binop_prec = {["+"]=1, ["-"]= 1, ["*"]=2, ["/"]=2}
unop_prec = {["-"]=3, ["+"]=3}
binop_assoc = {["+"]="left", ["-"]="left", ["*"]="left", ["/"]="left"}

function get_operator(text)
  if text:match("[+-/*]") then
    return {Binary, text:consume_pattern("[+-/*]")}
  else
    return nil
  end
end

function get_unary_operator(text)
  if text:match("[+-]") then
    return {Unary, text:consume_pattern("[+-]")}
  else
    return nil
  end
end

function is_binary(op)
  return op[1] == Binary
end

function op_greater(op1, op2)
  op1_type, op1_op = unpack(op1)
  op2_type, op2_op = unpack(op2)
  if op2_type == Unary then
    return false
  elseif op1_type == Unary then
    if unop_prec[op1_op] >= binop_prec[op2_op] then
      return true
    else
      return false
    end
  elseif binop_prec[op1_op] > binop_prec[op2_op] or
         (binop_prec[op1_op] == binop_prec[op2_op] and binop_assoc[op1_op] == "left") then
    return true
  else
    return false
  end
end

function parse(text)
  local operators = {}
  local operands = {}
  parse_term(text, operators, operands)
  local operator = get_operator(text)
  while operator do
    push_operator(operator, operators, operands)
    parse_term(text, operators, operands)
    operator = get_operator(text)
  end

  while #operators > 0 do
    pop_operator(operators, operands)
  end
  return operands
end

function parse_term(text, operators, operands)
    local unary_op = get_unary_operator(text)
    while unary_op do
      push_operator(unary_op, operators, operands)
      unary_op = get_unary_operator(text)
    end
    table.insert(operands, get_primary(text))
end

function push_operator(operator, operators, operands)
  while #operators > 0 and op_greater(operators[#operators], operator) do
    pop_operator(operators, operands)
  end
  table.insert(operators, operator)
end

function pop_operator(operators, operands)
  local operator = table.remove(operators)
  if is_binary(operator) then
    local o2 = table.remove(operands)
    local o1 = table.remove(operands)
    table.insert(operands, {operator[2], o1, o2})
  else
    table.insert(operands, {operator[2], table.remove(operands)})
  end
end

text = CharStream:new("-2+3*-(3+4)")
text:ignore("whitespace")
print(serialize(parse(text)))

