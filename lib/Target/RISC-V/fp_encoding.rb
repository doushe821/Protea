require_relative 'encoding'
require_relative '../../ADL/base'

module SimInfra
  def freg(name)
    [name, :f64, "let :#{name}, :FRegs, [:op], :f64, f_#{name}"]
  end
end

module SimInfra
  def format_r4_fp(opcode, funct2, rm)
    [:R4_FP, [
      field(:f_opcode, 6, 0, opcode),
      field(:f_frd, 11, 7),
      field(:f_rm, 14, 12, rm),
      field(:f_frs1, 19, 15),
      field(:f_frs2, 24, 20),
      field(:f_frs3, 31, 27),
      field(:f_funct2, 26, 25, funct2)
    ], freg(:frs3), freg(:frs2), freg(:frs1), freg(:frd)]
  end

  def format_r_fp(opcode, funct7, rm)
    [:R_FP, [
      field(:f_opcode, 6, 0, opcode),
      field(:f_frd, 11, 7),
      field(:f_rm, 14, 12, rm),
      field(:f_frs1, 19, 15),
      field(:f_frs2, 24, 20),
      field(:f_funct7, 31, 25, funct7)
    ], freg(:frs2), freg(:frs1), freg(:frd)]
  end

  def format_r_fp_comp(opcode, funct3, funct7)
    [:R_FP_COMP, [
      field(:f_opcode, 6, 0, opcode),
      field(:f_rd, 11, 7),
      field(:f_funct3, 14, 12, funct3),
      field(:f_frs1, 19, 15),
      field(:f_frs2, 24, 20),
      field(:f_funct7, 31, 25, funct7)
    ], freg(:frs2), freg(:frs1), xreg(:rd)]
  end

  def format_r_fp_class(opcode, funct3, funct5, funct7)
    [:R_FP_CLASS, [
      field(:f_opcode, 6, 0, opcode),
      field(:f_rd, 11, 7),
      field(:f_funct3, 14, 12, funct3),
      field(:f_frs1, 19, 15),
      field(:f_funct5, 24, 20, funct5),
      field(:f_funct7, 31, 25, funct7)
    ], freg(:frs1), xreg(:rd)]
  end

  def format_r_fp_no_rm(opcode, funct3, funct7)
    [:R_FP_NO_RM, [
      field(:f_opcode, 6, 0, opcode),
      field(:f_frd, 11, 7),
      field(:f_funct3, 14, 12, funct3),
      field(:f_frs1, 19, 15),
      field(:f_frs2, 24, 20),
      field(:f_funct7, 31, 25, funct7)
    ], freg(:frs2), freg(:frs1), freg(:frd)]
  end

  def format_r_fp_fcvt_frd(opcode, funct5, funct7, rm)
    [:R_FCVT, [
      field(:f_opcode, 6, 0, opcode),
      field(:f_frd, 11, 7),
      field(:f_rm, 14, 12, rm),
      field(:f_rs1, 19, 15),
      field(:f_funct5, 24, 20, funct5),
      field(:f_funct7, 31, 25, funct7)
    ], xreg(:rs1), freg(:frd)]
  end

  def format_r_fp_fcvt_rd(opcode, funct5, funct7, rm)
    [:R_FCVT, [
      field(:f_opcode, 6, 0, opcode),
      field(:f_rd, 11, 7),
      field(:f_rm, 14, 12, rm),
      field(:f_frs1, 19, 15),
      field(:f_funct5, 24, 20, funct5),
      field(:f_funct7, 31, 25, funct7)
    ], freg(:frs1), xreg(:rd)]
  end

  def format_r_fp_no_rm_move_rd(opcode, funct3, funct7)
    [:R_FCVT, [
      field(:f_opcode, 6, 0, opcode),
      field(:f_rd, 11, 7),
      field(:f_funct3, 14, 12, funct3),
      field(:f_frs1, 19, 15),
      field(:f_funct5, 24, 20, 0b00000),
      field(:f_funct7, 31, 25, funct7)
    ], freg(:frs1), xreg(:rd)]
  end

  def format_r_fp_no_rm_move_frd(opcode, funct3, funct7)
    [:R_FCVT, [
      field(:f_opcode, 6, 0, opcode),
      field(:f_frd, 11, 7),
      field(:f_funct3, 14, 12, funct3),
      field(:f_rs1, 19, 15),
      field(:f_funct5, 24, 20, 0b00000),
      field(:f_funct7, 31, 25, funct7)
    ], xreg(:rs1), freg(:frd)]
  end

  def format_i_fp(opcode, funct3)
    [:I, [
      field(:f_opcode, 6, 0, opcode),
      field(:f_frd, 11, 7),
      field(:f_funct3, 14, 12, funct3),
      field(:f_rs1, 19, 15),
      field(:f_imm, 31, 20)
    ], i_imm(:imm), xreg(:rs1), freg(:frd)]
  end

  def format_s_fp(opcode, func3)
    [:S, [
      field(:f_opcode, 6, 0, opcode),
      field(:func3, 14, 12, func3),
      field(:f_imm4_0, 11, 7),
      field(:f_rs1, 19, 15),
      field(:f_frs2, 24, 20),
      field(:f_imm11_5, 31, 25)
    ], s_imm(:imm), xreg(:rs1), freg(:frs2)]
  end
end
