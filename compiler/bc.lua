--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  bc.lua

  A quick and dirty module for writing files in Bitcode format.

  Copyright (c) 2007 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

module("bc", package.seeall)

END_BLOCK = 0
ENTER_SUBBLOCK = 1
DEFINE_ABBREV = 2
UNABBREV_RECORD = 3

ENCODING_FIXED = 1
ENCODING_VBR = 2
ENCODING_ARRAY = 3
ENCODING_CHAR6 = 4

BLOCKINFO = 0

SETBID = 1

define_class("LiteralOp")
function LiteralOp:initialize(value)
  self.value = value
end

define_class("VBROp")
function VBROp:initialize(bits)
  self.bits = bits
end

define_class("FixedOp")
function FixedOp:initialize(bits)
  self.bits = bits
end

define_class("ArrayOp")
function ArrayOp:initialize(elem_type)
  self.elem_type = elem_type
end

define_class("File")
function File:initialize(filename, app_magic_number)
  self.file = io.open(filename, "w")
  self.current_byte = 0
  self.current_bits = 0
  self.file:write("BC")
  self.file:write(app_magic_number)
  self.current_abbrev_width = 2
  self.offset = 0
  self.stack = {}
end

-- Witness the joy of trying to do bitwise manipulation in a language that
-- has no bitwise operators.
function File:write_fixed(val, bits)
  -- print(string.format("Write fixed: %d, %d", val, bits))
  -- print(string.format("Existing bytes(%d): %d", self.current_bits, self.current_byte))
  while bits > 0 do
    local bits_this_byte = math.min(8-self.current_bits, bits)
    local low_bits = val % (2 ^ bits_this_byte)
    self.current_byte = self.current_byte + (low_bits * (2 ^ self.current_bits))
    self.current_bits = self.current_bits + bits_this_byte
    if self.current_bits == 8 then
      -- print(string.format("Flushing byte %d", self.current_byte))
      self.file:write(string.char(self.current_byte))
      self.current_byte = 0
      self.current_bits = 0
      self.offset = self.offset + 1
    end
    bits = bits - bits_this_byte
    val = math.floor(val / (2 ^ bits_this_byte))
  end
end

function File:align_32_bits()
  if self.current_bits > 0 then
    self:write_fixed(0, 8-self.current_bits)
  end

  if self.offset % 4 > 0 then
    self:write_fixed(0, (4 - (self.offset % 4)) * 8)
  end
end

function File:write_vbr(val, bits)
  -- print(string.format("Write VBR: %d, %d", val, bits))
  local high_bit = 2 ^ (bits-1)
  local bits_remaining

  if val == 0 then
    bits_remaining = 1
  else
    bits_remaining = 1 + math.floor(math.log(val) / math.log(2))
  end

  while true do
    if bits_remaining > (bits-1) then
      self:write_fixed(high_bit + (val % high_bit), bits)
      bits_remaining = bits_remaining - (bits-1)
      val = math.floor(val / high_bit)
    else
      self:write_fixed(val, bits)
      break
    end
  end
end

function File:enter_subblock(block_id)
  -- print(string.format("++ Enter subblock: %d", block_id))
  local old_abbrev_width = self.current_abbrev_width
  self:write_fixed(ENTER_SUBBLOCK, self.current_abbrev_width)
  self:write_vbr(block_id, 8)
  self:write_vbr(4, 4)  -- no need to make this configurable at the moment
  self.current_abbrev_width = 4
  self:align_32_bits()

  self:write_fixed(0, 32)   -- we'll fill this in later
  table.insert(self.stack, {old_abbrev_width, self.file:seek()})
end

function File:end_subblock(block_id)
  -- print(string.format("-- End subblock: %d", block_id))
  self:write_fixed(END_BLOCK, self.current_abbrev_width)
  self:align_32_bits()
  local block_offset
  self.current_abbrev_width, block_offset = unpack(table.remove(self.stack))
  local current_offset = self.file:seek()
  self.file:seek("set", block_offset - 4)
  self:write_fixed((current_offset - block_offset) / 4, 32)
  self.file:seek("set", current_offset)
end

function File:write_unabbreviated_record(id, ...)
  -- print(string.format("Write unabbreviated record: %d", id))
  local args = {...}
  self:write_fixed(UNABBREV_RECORD, self.current_abbrev_width)
  self:write_vbr(id, 6)
  self:write_vbr(#args, 6)
  for arg in each(args) do
    self:write_vbr(arg, 6)
  end
end

function File:write_abbreviated_val(val, op)
  if op.class == VBROp then
    self:write_vbr(val, op.bits)
  elseif op.class == FixedOp then
    self:write_fixed(val, op.bits)
  else
    error("Unknown op type!")
  end
end

function File:write_abbreviated_record(abbreviation, ...)
  local args = {...}
  -- print("Write abbreviated record:" .. serialize({...}))
  --      ", #args: " .. #args .. ", expected #args: " .. #abbreviation.ops)
  if #args ~= #abbreviation.ops then
    error("Wrong number of arguments for abbreviated record")
  end
  self:write_fixed(abbreviation.id, self.current_abbrev_width)
  for i, arg in ipairs(args) do
    local op = abbreviation.ops[i]
    if op.class == ArrayOp then
      if type(arg) == "string" then
        self:write_vbr(arg:len(), 6)
        for int in each({arg:byte(1, arg:len())}) do
          self:write_abbreviated_val(int, op.elem_type)
        end
      else
        self:write_vbr(#arg, 6)
        for int in each(arg) do
          self:write_abbreviated_val(int, op.elem_type)
        end
      end
    else
      self:write_abbreviated_val(arg, op)
    end
  end
end

function File:write_abbrev_op(arg)
  if arg.class == LiteralOp then
    self:write_fixed(1, 1)
    self:write_vbr(arg.value, 8)
  elseif arg.class == VBROp then
    self:write_fixed(0, 1)
    self:write_fixed(ENCODING_VBR, 3)
    self:write_vbr(arg.bits, 5)
  elseif arg.class == FixedOp then
    self:write_fixed(0, 1)
    self:write_fixed(ENCODING_FIXED, 3)
    self:write_vbr(arg.bits, 5)
  else
    error("Unknown/unhandled op type")
  end
end

function File:define_abbreviation(abbrev_id, ...)
  local abbrev = {id=abbrev_id, ops={}}
  local args = {...}
  self:write_fixed(DEFINE_ABBREV, self.current_abbrev_width)
  if args[#args].class == ArrayOp then
    self:write_vbr(#args+1, 5)
  else
    self:write_vbr(#args, 5)
  end

  for arg in each(args) do
    if arg.class ~= LiteralOp then
      table.insert(abbrev.ops, arg)
    end

    if arg.class == ArrayOp then
      self:write_fixed(0, 1)
      self:write_fixed(ENCODING_ARRAY, 3)
      self:write_abbrev_op(arg.elem_type)
    else
      self:write_abbrev_op(arg)
    end
  end
  return abbrev
end

-- vim:et:sts=2:sw=2
