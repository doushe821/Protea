require_relative 'encoding'
require_relative '../../ADL/base'
require_relative '../../ADL/builder'

module RV64F
  include SimInfra
  extend SimInfra
  # NOTE: semantics now are just dummies, they will change in future
  # Register float regs in regfile
  RegisterFile(:FRegs) do
    (0..31).each do |i|
      send(:f64, :"f#{i}")
    end
  end

  # Basic arithmetic
  Instruction(:fadd_s) do
    encoding(*format_r_fp(0b1010011, 0b0000000))
    asm { 'fadd.s {frd}, {frs1}, {frs2}' }
    code do
      frd[] = f32_add(frs1, frs2)
    end
  end

  Instruction(:fadd_d) do
    encoding(*format_r_fp(0b1010011, 0b0000001))
    asm { 'fadd.d {frd}, {frs1}, {frs2}' }
    code do
      frd[] = f64_add(frs1, frs2)
    end
  end

  Instruction(:fsub_s) do
    encoding(*format_r_fp(0b1010011, 0b0000100))
    asm { 'fsub.s {frd}, {frs1}, {frs2}' }
    code do
      frd[] = f32_sub(frs1, frs2)
    end
  end

  Instruction(:fsub_d) do
    encoding(*format_r_fp(0b1010011, 0b0000101))
    asm { 'fsub.d {frd}, {frs1}, {frs2}' }
    code do
      frd[] = f64_sub(frs1, frs2)
    end
  end

  Instruction(:fmul_s) do
    encoding(*format_r_fp(0b1010011, 0b0001000))
    asm { 'fmul.s {frd}, {frs1}, {frs2}' }
    code do
      frd[] = f32_mul(frs1, frs2)
    end
  end

  Instruction(:fmul_d) do
    encoding(*format_r_fp(0b1010011, 0b0001001))
    asm { 'fmul.d {frd}, {frs1}, {frs2}' }
    code do
      frd[] = f64_mul(frs1, frs2)
    end
  end

  Instruction(:fdiv_s) do
    encoding(*format_r_fp(0b1010011, 0b0001100))
    asm { 'fdiv.s {frd}, {frs1}, {frs2}' }
    code do
      frd[] = f32_div(frs1, frs2)
    end
  end

  Instruction(:fdiv_d) do
    encoding(*format_r_fp(0b1010011, 0b0001101))
    asm { 'fdiv.d {frd}, {frs1}, {frs2}' }
    code do
      frd[] = f64_div(frs1, frs2)
    end
  end

  Instruction(:fsqrt_s) do
    encoding(*format_r_fp(0b1010011, 0b0101100))
    asm { 'fsqrt.s {frd}, {frs1}' }
    code do
      frd[] = f32_sqrt(frs1)
    end
  end

  Instruction(:fsqrt_d) do
    encoding(*format_r_fp(0b1010011, 0b0101101))
    asm { 'fsqrt.d {frd}, {frs1}' }
    code do
      frd[] = f64_sqrt(frs1)
    end
  end

  # Memory
  Instruction(:flw) do
    encoding(*format_i_fp(0b0000111, 0b010))
    asm { 'flw {frd}, {imm}({rs1})' }
    code do
      frd[] = mem[rs1 + imm, :b32]
    end
  end

  Instruction(:fld) do
    encoding(*format_i_fp(0b0000111, 0b011))
    asm { 'fld {frd}, {imm}({rs1})' }
    code do
      frd[] = mem[rs1 + imm, :b64]
    end
  end

  Instruction(:fsw) do
    encoding(*format_s_fp(0b0100111, 0b010))
    asm { 'fsw {frs2}, {imm}({rs1})' }
    code do
      mem[rs1 + imm] = frs2[31, 0]
    end
  end

  Instruction(:fsd) do
    encoding(*format_s_fp(0b0100111, 0b011))
    asm { 'fsd {frs2}, {imm}({rs1})' }
    code do
      mem[rs1 + imm] = frs2[63, 0]
    end
  end

  # Fused Mul/Add
  Instruction(:fmadd_s) do
    encoding(*format_r4_fp(0b1000011, 0b0))
    asm { 'fmadd.s {frd}, {frs1}, {frs2}, {frs3}' }
    code do
      frd[] = f32_mul_add(frs1, frs2, frs3)
    end
  end

  Instruction(:fmadd_d) do
    encoding(*format_r4_fp(0b1000011, 0b01))
    asm { 'fmadd.d {frd}, {frs1}, {frs2}, {frs3}' }
    code do
      frd[] = f64_mul_add(frs1, frs2, frs3)
    end
  end

  Instruction(:fmsub_s) do
    encoding(*format_r4_fp(0b1000111, 0b0))
    asm { 'fmsub.s {frd}, {frs1}, {frs2}, {frs3}' }
    code do
      frd[] = f32_mul_sub(frs1, frs2, frs3)
    end
  end

  Instruction(:fmsub_d) do
    encoding(*format_r4_fp(0b1000111, 0b01))
    asm { 'fmsub.d {frd}, {frs1}, {frs2}, {frs3}' }
    code do
      frd[] = f64_mul_sub(frs1, frs2, frs3)
    end
  end

  Instruction(:fnmadd_s) do
    encoding(*format_r4_fp(0b1001111, 0b00))
    asm { 'fnmadd.s {frd}, {frs1}, {frs2}, {frs3}' }
    code do
      frd[] = f32_mul_add_n(frs1, frs2, frs3)
    end
  end

  Instruction(:fnmadd_d) do
    encoding(*format_r4_fp(0b1001111, 0b01))
    asm { 'fnmadd.d {frd}, {frs1}, {frs2}, {frs3}' }
    code do
      frd[] = f64_mul_add_n(frs1, frs2, frs3)
    end
  end

  Instruction(:fnmsub_s) do
    encoding(*format_r4_fp(0b1001011, 0b00))
    asm { 'fnmsub.s {frd}, {frs1}, {frs2}, {frs3}' }
    code do
      frd[] = f32_mul_sub_n(frs1, frs2, frs3)
    end
  end

  Instruction(:fnmsub_d) do
    encoding(*format_r4_fp(0b1001011, 0b01))
    asm { 'fnmsub.d {frd}, {frs1}, {frs2}, {frs3}' }
    code do
      frd[] = f64_mul_sub_n(frs1, frs2, frs3)
    end
  end

  # Sign injection
  Instruction(:fsgnj_s) do
    encoding(*format_r_fp_no_rm(0b1010011, 0b000, 0b0010000))
    asm { 'fsgnj.s {frd}, {frs1}, {frs2}' }
    code do
      frd[] = f32_sign_injection(frs1, frs2)
    end
  end

  Instruction(:fsgnj_d) do
    encoding(*format_r_fp_no_rm(0b1010011, 0b000, 0b0010001))
    asm { 'fsgnj.d {frd}, {frs1}, {frs2}' }
    code do
      frd[] = f64_sign_injection(frs1, frs2)
    end
  end

  Instruction(:fsgnjn_s) do
    encoding(*format_r_fp_no_rm(0b1010011, 0b001, 0b0010000))
    asm { 'fsgnjn.s {frd}, {frs1}, {frs2}' }
    code do
      frd[] = f32_sign_injection_n(frs1, frs2)
    end
  end

  Instruction(:fsgnjn_d) do
    encoding(*format_r_fp_no_rm(0b1010011, 0b001, 0b0010001))
    asm { 'fsgnjn.d {frd}, {frs1}, {frs2}' }
    code do
      frd[] = f64_sign_injection_n(frs1, frs2)
    end
  end

  Instruction(:fsgnjx_s) do
    encoding(*format_r_fp_no_rm(0b1010011, 0b010, 0b0010000))
    asm { 'fsgnjx.s {frd}, {frs1}, {frs2}' }
    code do
      frd[] = f32_sign_xor(frs1, frs2)
    end
  end

  Instruction(:fsgnjx_d) do
    encoding(*format_r_fp_no_rm(0b1010011, 0b010, 0b0010001))
    asm { 'fsgnjx.d {frd}, {frs1}, {frs2}' }
    code do
      frd[] = f64_sign_xor(frs1, frs2)
    end
  end

  # Comparisons
  Instruction(:fmin_s) do
    encoding(*format_r_fp_no_rm(0b1010011, 0b000, 0b0010100))
    asm { 'fmin.s {frd}, {frs1}, {frs2}' }
    code do
      frd[] = f32_min(frs1, frs2)
    end
  end

  Instruction(:fmin_d) do
    encoding(*format_r_fp_no_rm(0b1010011, 0b000, 0b0010101))
    asm { 'fmin.d {frd}, {frs1}, {frs2}' }
    code do
      frd[] = f64_min(frs1, frs2)
    end
  end

  Instruction(:fmax_s) do
    encoding(*format_r_fp_no_rm(0b1010011, 0b001, 0b0010100))
    asm { 'fmax.s {frd}, {frs1}, {frs2}' }
    code do
      frd[] = f32_max(frs1, frs2)
    end
  end

  Instruction(:fmax_d) do
    encoding(*format_r_fp_no_rm(0b1010011, 0b001, 0b0010101))
    asm { 'fmax.d {frd}, {frs1}, {frs2}' }
    code do
      frd[] = f64_max(frs1, frs2)
    end
  end

  Instruction(:feq_s) do
    encoding(*format_r_fp_comp(0b1010011, 0b010, 0b1010000))
    asm { 'feq.s {rd}, {frs1}, {frs2}' }
    code do
      rd[] = f32_eq(frs1, frs2)
    end
  end

  Instruction(:feq_d) do
    encoding(*format_r_fp_comp(0b1010011, 0b010, 0b1010001))
    asm { 'feq.d {rd}, {frs1}, {frs2}' }
    code do
      rd[] = f64_eq(frs1, frs2)
    end
  end

  Instruction(:flt_s) do
    encoding(*format_r_fp_comp(0b1010011, 0b001, 0b1010000))
    asm { 'flt.s {rd}, {frs1}, {frs2}' }
    code do
      rd[] = f32_lt(frs1, frs2)
    end
  end

  Instruction(:flt_d) do
    encoding(*format_r_fp_comp(0b1010011, 0b001, 0b1010001))
    asm { 'flt.d {rd}, {frs1}, {frs2}' }
    code do
      rd[] = f64_lt(frs1, frs2)
    end
  end

  Instruction(:fle_s) do
    encoding(*format_r_fp_comp(0b1010011, 0b000, 0b1010000))
    asm { 'fle.s {rd}, {frs1}, {frs2}' }
    code do
      rd[] = f32_le(frs1, frs2)
    end
  end

  Instruction(:fle_d) do
    encoding(*format_r_fp_comp(0b1010011, 0b000, 0b1010001))
    asm { 'fle.d {rd}, {frs1}, {frs2}' }
    code do
      rd[] = f64_le(frs1, frs2)
    end
  end

  # Conversions
  Instruction(:fcvt_w_s) do
    encoding(*format_r_fp_fcvt_rd(0b1010011, 0b00000, 0b1100000))
    asm { 'fcvt.w.s {rd}, {frs1}' }
    code do
      rd[] = f32_to_i32(frs1)
    end
  end

  Instruction(:fcvt_wu_s) do
    encoding(*format_r_fp_fcvt_rd(0b1010011, 0b00001, 0b1100000))
    asm { 'fcvt.wu.s {rd}, {frs1}' }
    code do
      rd[] = f32_to_u32(frs1)
    end
  end

  Instruction(:fcvt_l_s) do
    encoding(*format_r_fp_fcvt_rd(0b1010011, 0b00010, 0b1100000))
    asm { 'fcvt.l.s {rd}, {frs1}' }
    code do
      rd[] = f32_to_i64(frs1)
    end
  end

  Instruction(:fcvt_lu_s) do
    encoding(*format_r_fp_fcvt_rd(0b1010011, 0b00011, 0b1100000))
    asm { 'fcvt.lu.s {rd}, {frs1}' }
    code do
      rd[] = f32_to_u64(frs1)
    end
  end

  Instruction(:fcvt_s_w) do
    encoding(*format_r_fp_fcvt_frd(0b1010011, 0b00000, 0b1101000))
    asm { 'fcvt.s.w {frd}, {rs1}' }
    code do
      frd[] = i32_to_f32(rs1)
    end
  end

  Instruction(:fcvt_s_wu) do
    encoding(*format_r_fp_fcvt_frd(0b1010011, 0b00001, 0b1101000))
    asm { 'fcvt.s.wu {frd}, {rs1}' }
    code do
      frd[] = u32_to_f32(rs1)
    end
  end

  Instruction(:fcvt_s_l) do
    encoding(*format_r_fp_fcvt_frd(0b1010011, 0b00010, 0b1101000))
    asm { 'fcvt.s.l {frd}, {rs1}' }
    code do
      frd[] = i64_to_f32(rs1)
    end
  end

  Instruction(:fcvt_s_lu) do
    encoding(*format_r_fp_fcvt_frd(0b1010011, 0b00011, 0b1101000))
    asm { 'fcvt.s.lu {frd}, {rs1}' }
    code do
      frd[] = u64_to_f32(rs1)
    end
  end

  # Classification
  Instruction(:fclass_s) do
    encoding(*format_r_fp_class(0b1010011, 0b001, 0b00000, 0b1110000))
    asm { 'fclass.s {rd}, {frs1}' }
    code do
      rd[] = f32_classify(frs1)
    end
  end

  Instruction(:fclass_d) do
    encoding(*format_r_fp_class(0b1010011, 0b001, 0b00000, 0b1110001))
    asm { 'fclass.d {rd}, {frs1}' }
    code do
      rd[] = f64_classify(frs1)
    end
  end

  # Move
  Instruction(:fmv_x_w) do
    encoding(*format_r_fp_no_rm_move_rd(0b1010011, 0b000, 0b1110000))
    asm { 'fmv.x.w {rd}, {frs1}' }
    code do
      rd[] = frs1[31, 0]
    end
  end

  Instruction(:fmv_w_x) do
    encoding(*format_r_fp_no_rm_move_frd(0b1010011, 0b000, 0b1111000))
    asm { 'fmv.w.x {frd}, {rs1}' }
    code do
      frd[] = rs1[31, 0]
    end
  end
end
