require_relative 'encoding'
require_relative '../../ADL/base'
require_relative '../../ADL/builder'

module RV32I
  include SimInfra
  extend SimInfra

  Interface do
    function :sysCall
  end

  RegisterFile(:XRegs) do
    r32 :x0, zero
    r32  :x1
    r32  :x2
    r32  :x3
    r32  :x4
    r32  :x5
    r32  :x6
    r32  :x7
    r32  :x8
    r32  :x9
    r32 :x10
    r32 :x11
    r32 :x12
    r32 :x13
    r32 :x14
    r32 :x15
    r32 :x16
    r32 :x17
    r32 :x18
    r32 :x19
    r32 :x20
    r32 :x21
    r32 :x22
    r32 :x23
    r32 :x24
    r32 :x25
    r32 :x26
    r32 :x27
    r32 :x28
    r32 :x29
    r32 :x30
    r32 :x31
    r32 :pc, pc
  end

  Instruction(:lui) do
    encoding(*format_u(0b0110111))
    asm { 'lui {rd}, {imm}' }
    code { rd[] = imm }
  end

  Instruction(:auipc) do
    encoding(*format_u(0b0010111))
    asm { 'auipc {rd}, {imm}' }
    code { rd[] = imm + pc }
  end

  Instruction(:add) do
    encoding(*format_r(0b0110011, 0b000, 0b0000000))
    asm { 'add {rd}, {rs1}, {rs2}' }
    code { rd[] = rs1.u + rs2.u }
  end

  Instruction(:sub) do
    encoding(*format_r(0b0110011, 0b000, 0b0100000))
    asm { 'sub {rd}, {rs1}, {rs2}' }
    code { rd[] = rs1.u - rs2.u }
  end

  Instruction(:sll) do
    encoding(*format_r(0b0110011, 0b001, 0b0000000))
    asm { 'sll {rd}, {rs1}, {rs2}' }
    code { rd[] = rs1.u << rs2.u }
  end

  Instruction(:slt) do
    encoding(*format_r(0b0110011, 0b010, 0b0000000))
    asm { 'slt {rd}, {rs1}, {rs2}' }
    code { rd[] = (rs1.s < rs2.s).b32 }
  end

  Instruction(:sltu) do
    encoding(*format_r(0b0110011, 0b011, 0b0000000))
    asm { 'sltu {rd}, {rs1}, {rs2}' }
    code { rd[] = (rs1.u < rs2.u).b32 }
  end

  Instruction(:xor) do
    encoding(*format_r(0b0110011, 0b100, 0b0000000))
    asm { 'xor {rd}, {rs1}, {rs2}' }
    code { rd[] = rs1 ^ rs2 }
  end

  Instruction(:srl) do
    encoding(*format_r(0b0110011, 0b101, 0b0000000))
    asm { 'srl {rd}, {rs1}, {rs2}' }
    code { rd[] = rs1.u >> rs2.u }
  end

  Instruction(:sra) do
    encoding(*format_r(0b0110011, 0b101, 0b0100000))
    asm { 'sra {rd}, {rs1}, {rs2}' }
    code { rd[] = rs1.s >> rs2.s }
  end

  Instruction(:or) do
    encoding(*format_r(0b0110011, 0b110, 0b0000000))
    asm { 'or {rd}, {rs1}, {rs2}' }
    code { rd[] = rs1 | rs2 }
  end

  Instruction(:and) do
    encoding(*format_r(0b0110011, 0b111, 0b0000000))
    asm { 'and {rd}, {rs1}, {rs2}' }
    code { rd[] = rs1 & rs2 }
  end

  Instruction(:addi) do
    encoding(*format_i(0b0010011, 0b000))
    asm { 'addi {rd}, {rs1}, {imm}' }
    code { rd[] = rs1 + imm }
  end

  Instruction(:slti) do
    encoding(*format_i(0b0010011, 0b010))
    asm { 'slti {rd}, {rs1}, {imm}' }
    code { rd[] = (rs1.s < imm).b32 }
  end

  Instruction(:sltiu) do
    encoding(*format_i(0b0010011, 0b011))
    asm { 'sltiu {rd}, {rs1}, {imm}' }
    code { rd[] = (rs1.u < imm.u).b32 }
  end

  Instruction(:xori) do
    encoding(*format_i(0b0010011, 0b100))
    asm { 'xori {rd}, {rs1}, {imm}' }
    code { rd[] = rs1 ^ imm }
  end

  Instruction(:ori) do
    encoding(*format_i(0b0010011, 0b110))
    asm { 'ori {rd}, {rs1}, {imm}' }
    code { rd[] = rs1 | imm }
  end

  Instruction(:andi) do
    encoding(*format_i(0b0010011, 0b111))
    asm { 'andi {rd}, {rs1}, {imm}' }
    code { rd[] = rs1 & imm }
  end

  Instruction(:slli) do
    encoding(*format_i_shift(0b0010011, 0b001, 0b00000))
    asm { 'slli {rd}, {rs1}, {imm}' }
    code { rd[] = rs1 << imm }
  end

  Instruction(:srli) do
    encoding(*format_i_shift(0b0010011, 0b101, 0b00000))
    asm { 'srli {rd}, {rs1}, {imm}' }
    code { rd[] = rs1 >> imm }
  end

  Instruction(:srai) do
    encoding(*format_i_shift(0b0010011, 0b101, 0b01000))
    asm { 'srai {rd}, {rs1}, {imm}' }
    code { rd[] = rs1.s >> imm }
  end

  Instruction(:beq) do
    encoding(*format_b(0b1100011, 0b000))
    asm { 'beq {rs1}, {rs2}, {imm}' }
    code { branch(select(rs1 == rs2, pc + imm, pc + xlen)) }
  end

  Instruction(:bne) do
    encoding(*format_b(0b1100011, 0b001))
    asm { 'bne {rs1}, {rs2}, {imm}' }
    code { branch(select(rs1 != rs2, pc + imm, pc + xlen)) }
  end

  Instruction(:blt) do
    encoding(*format_b(0b1100011, 0b100))
    asm { 'blt {rs1}, {rs2}, {imm}' }
    code { branch(select(rs1.s < rs2.s, pc + imm, pc + xlen)) }
  end

  Instruction(:bge) do
    encoding(*format_b(0b1100011, 0b101))
    asm { 'bge {rs1}, {rs2}, {imm}' }
    code { branch(select(rs1.s >= rs2.s, pc + imm, pc + xlen)) }
  end

  Instruction(:bltu) do
    encoding(*format_b(0b1100011, 0b110))
    asm { 'bltu {rs1}, {rs2}, {imm}' }
    code { branch(select(rs1.u < rs2.u, pc + imm, pc + xlen)) }
  end

  Instruction(:bgeu) do
    encoding(*format_b(0b1100011, 0b111))
    asm { 'bgeu {rs1}, {rs2}, {imm}' }
    code { branch(select(rs1.u >= rs2.u, pc + imm, pc + xlen)) }
  end

  Instruction(:jal) do
    encoding(*format_j(0b1101111))
    asm { 'jal {rd}, {imm}' }
    code do
      rd[] = pc + xlen
      branch(pc + imm)
    end
  end

  Instruction(:jalr) do
    encoding(*format_i(0b1100111, 0b000))
    asm { 'jalr {rd}, {rs1}, {imm}' }
    code do
      let :t, :b32, pc + xlen
      branch((rs1 + imm) & (~1))
      rd[] = t
    end
  end

  Instruction(:sb) do
    encoding(*format_s(0b0100011, 0b000))
    asm { 'sb {rs2}, {imm}({rs1})' }
    code { mem[rs1 + imm] = rs2[7, 0] }
  end

  Instruction(:sh) do
    encoding(*format_s(0b0100011, 0b001))
    asm { 'sh {rs2}, {imm}({rs1})' }
    code { mem[rs1 + imm] = rs2[15, 0] }
  end

  Instruction(:sw) do
    encoding(*format_s(0b0100011, 0b010))
    asm { 'sw {rs2}, {imm}({rs1})' }
    code { mem[rs1 + imm] = rs2 }
  end

  Instruction(:lb) do
    encoding(*format_i(0b0000011, 0b000))
    asm { 'lb {rd}, {imm}({rs1})' }
    code { rd[] = mem[rs1 + imm, :b8].s32 }
  end

  Instruction(:lh) do
    encoding(*format_i(0b0000011, 0b001))
    asm { 'lh {rd}, {imm}({rs1})' }
    code { rd[] = mem[rs1 + imm, :b16].s32 }
  end

  Instruction(:lw) do
    encoding(*format_i(0b0000011, 0b010))
    asm { 'lw {rd}, {imm}({rs1})' }
    code { rd[] = mem[rs1 + imm, :b32] }
  end

  Instruction(:lbu) do
    encoding(*format_i(0b0000011, 0b100))
    asm { 'lbu {rd}, {imm}({rs1})' }
    code { rd[] = mem[rs1 + imm, :b8].u32 }
  end

  Instruction(:lhu) do
    encoding(*format_i(0b0000011, 0b101))
    asm { 'lhu {rd}, {imm}({rs1})' }
    code { rd[] = mem[rs1 + imm, :b16].u32 }
  end

  Instruction(:ecall) do
    encoding :E, [field(:c, 31, 0, 0b1110011)]
    asm { 'ecall' }
    code { sysCall }
  end

  Instruction(:ebreak) do
    encoding :E, [field(:c, 31, 0, 0b100000000000001110011)]
    asm { 'ebreak' }
    code {}
  end

  Instruction(:fence) do
    encoding :E,
             [field(:c1, 31, 28, 0b0000), field(:c2, 27, 24), field(:c3, 23, 20),
              field(:c4, 19, 0, 0b00000000000000001111)]
    asm { 'fence' }
    code {}
  end
end
