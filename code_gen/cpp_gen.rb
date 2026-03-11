require 'Utility/helper_cpp'
# frozen_string_literal: true

# Semantics Generator: Converts IR to C++ code
module CodeGen
  class CppGenerator
    attr_reader :emitter, :mapping

    def initialize(emitter, mapping = {})
      @emitter = emitter
      @mapping = mapping
    end

    def binary_operation(emitter, operation, op_str)
      dst = @mapping[operation[:oprnds][0][:name]] || operation[:oprnds][0][:name]
      src1 = @mapping[operation[:oprnds][1][:name]] || operation[:oprnds][1][:name]
      src2 = @mapping[operation[:oprnds][2][:name]] || operation[:oprnds][2][:name]

      src1 = src1.nil? ? operation[:oprnds][1][:value] : src1
      src2 = src2.nil? ? operation[:oprnds][2][:value] : src2

      emitter.emit_line("#{dst} = #{src1} #{op_str} #{src2};")
    end

    def emit_fp_binary(opname, operation)
      dst  = map_operand(operation[:oprnds][0])
      src1 = map_operand(operation[:oprnds][1])
      src2 = map_operand(operation[:oprnds][2])

      @emitter.emit_line("#{dst} = #{opname}(#{src1}, #{src2});")
    end

    def emit_fp_unary(opname, operation)
      dst = map_operand(operation[:oprnds][0])
      src = map_operand(operation[:oprnds][1])

      @emitter.emit_line("#{dst} = #{opname}(#{src});")
    end

    def emit_fp_ternary(opname, operation)
      dst = map_operand(operation[:oprnds][0])
      src1 = map_operand(operation[:oprnds][1])
      src2 = map_operand(operation[:oprnds][2])
      src3 = map_operand(operation[:oprnds][3])

      @emitter.emit_line("#{dst} = #{opname}(#{src1}, #{src2}, #{src3});")
    end

    def map_n_operands(op, n)
      ops = []
      (0...n).each do |i|
        ops[i] = map_operand(op[:oprnds][i])
      end
      ops
    end

    def map_operand(op)
      val = @mapping[op[:name]] || op[:name]
      val.nil? ? op[:value] : val
    end

    def self.generate_statement(operation)
      emitter = Utility::GenEmitter.new
      CppGenerator.new(emitter, operation[:attrs][:mapping]).generate_statement(operation)
      emitter.to_s
    end

    def cpu_write_reg(dst)
      "cpu.set#{dst[:regset]}"
    end

    def cpu_read_reg(dst)
      "cpu.get#{dst[:regset]}"
    end

    def cpu_write_mem(addr, val)
      "cpu.m_memory->write(#{addr}, #{val})"
    end

    def cpu_read_mem(dst, addr)
      "cpu.m_memory->read<#{Utility::HelperCpp.gen_small_type(dst[:type])}>(#{addr})"
    end

    def generate_statement(operation)
      case operation[:name]
      when :add
        binary_operation(@emitter, operation, '+')
      when :sub
        binary_operation(@emitter, operation, '-')
      when :mul
        binary_operation(@emitter, operation, '*')
      when :div
        binary_operation(@emitter, operation, '/')
      when :shr
        binary_operation(@emitter, operation, '>>')
      when :shl
        binary_operation(@emitter, operation, '<<')
      when :and
        binary_operation(@emitter, operation, '&')
      when :or
        binary_operation(@emitter, operation, '|')
      when :xor
        binary_operation(@emitter, operation, '^')
      when :lt
        binary_operation(@emitter, operation, '<')
      when :gt
        binary_operation(@emitter, operation, '>')
      when :le
        binary_operation(@emitter, operation, '<=')
      when :ge
        binary_operation(@emitter, operation, '>=')
      when :eq
        binary_operation(@emitter, operation, '==')
      when :ne
        binary_operation(@emitter, operation, '!=')
      when :let
        dst = @mapping[operation[:oprnds][0][:name]] || operation[:oprnds][0][:name]
        src = @mapping[operation[:oprnds][1][:name]] || operation[:oprnds][1][:name]
        src = src.nil? ? operation[:oprnds][1][:value] : src
        @emitter.emit_line("#{dst} = #{src};")
      when :new_var
        var_name = operation[:oprnds][0][:name]
        var_type = Utility::HelperCpp.gen_type(operation[:oprnds][0][:type])
        @emitter.emit_line("#{var_type} #{var_name};")
      when :cast
        dst = @mapping[operation[:oprnds][0][:name]] || operation[:oprnds][0][:name]
        src = @mapping[operation[:oprnds][1][:name]] || operation[:oprnds][1][:name]
        src = src.nil? ? operation[:oprnds][1][:value] : src
        bitsize_dst = Utility.get_type(operation[:oprnds][0][:type]).bitsize
        bitsize_src = Utility.get_type(operation[:oprnds][1][:type]).bitsize
        cast_type = Utility::HelperCpp.gen_type(operation[:oprnds][0][:type])
        if Utility.get_type(operation[:oprnds][0][:type]).typeof == :s && bitsize_src < bitsize_dst
          @emitter.emit_line("#{dst} = (static_cast<#{cast_type}>(#{src}) << #{bitsize_dst - bitsize_src}) >> #{bitsize_dst - bitsize_src};")
        else
          @emitter.emit_line("#{dst} = static_cast<#{cast_type}>(#{src});")
        end
      when :readReg
        src = operation[:oprnds][1]
        src_name = @mapping[operation[:oprnds][1][:name]] || operation[:oprnds][1][:name]
        expr = @mapping[operation[:oprnds][0][:name]] || operation[:oprnds][0][:name]
        expr = expr.nil? ? operation[:oprnds][0][:value] : expr

        @emitter.emit_line("#{expr} = #{cpu_read_reg(src)}<#{Utility::HelperCpp.gen_small_type(src[:type])}>(#{src_name});")
      when :writeReg
        dst = operation[:oprnds][0]
        dst_name = @mapping[operation[:oprnds][0][:name]] || operation[:oprnds][0][:name]
        expr = @mapping[operation[:oprnds][1][:name]] || operation[:oprnds][1][:name]
        expr = expr.nil? ? operation[:oprnds][1][:value] : expr

        @emitter.emit_line("#{cpu_write_reg(dst)}(#{dst_name}, #{expr});")
      when :branch
        val = @mapping[operation[:oprnds][0][:name]] || operation[:oprnds][0][:name]
        @emitter.emit_line("cpu.setPC(#{val});")
      when :readMem
        dst = @mapping[operation[:oprnds][0][:name]] || operation[:oprnds][0][:name]
        addr = @mapping[operation[:oprnds][1][:name]] || operation[:oprnds][1][:name]
        @emitter.emit_line("#{dst} = #{cpu_read_mem operation[:oprnds][0], addr};")
      when :writeMem
        addr = @mapping[operation[:oprnds][0][:name]] || operation[:oprnds][0][:name]
        val = @mapping[operation[:oprnds][1][:name]] || operation[:oprnds][1][:name]
        @emitter.emit_line("#{cpu_write_mem addr, val};")
      when :extract
        dst = @mapping[operation[:oprnds][0][:name]] || operation[:oprnds][0][:name]
        src = @mapping[operation[:oprnds][1][:name]] || operation[:oprnds][1][:name]

        @emitter.emit_line("#{dst} = static_cast<#{Utility::HelperCpp.gen_small_type operation[:oprnds][0][:type]}>(#{src} << #{operation[:oprnds][3][:value]});")
      when :sysCall
        @emitter.emit_line('cpu.doExit();')
      when :select
        dst = @mapping[operation[:oprnds][0][:name]] || operation[:oprnds][0][:name]
        cond = @mapping[operation[:oprnds][1][:name]] || operation[:oprnds][1][:name]
        true_val = @mapping[operation[:oprnds][2][:name]] || operation[:oprnds][2][:name]
        false_val = @mapping[operation[:oprnds][3][:name]] || operation[:oprnds][3][:name]

        @emitter.emit_line("#{dst} = #{cond} ? #{true_val} : #{false_val};")

      # Floating point arithmetic binary operations
      when :f32_add then emit_fp_binary('f32_add', operation)
      when :f64_add then emit_fp_binary('f64_add', operation)

      when :f32_sub then emit_fp_binary('f32_sub', operation)
      when :f64_sub then emit_fp_binary('f64_sub', operation)

      when :f32_mul then emit_fp_binary('f32_mul', operation)
      when :f64_mul then emit_fp_binary('f64_mul', operation)

      when :f32_div then emit_fp_binary('f32_div', operation)
      when :f64_div then emit_fp_binary('f64_div', operation)
      # Floating point unary operations
      when :f32_sqrt then emit_fp_unary('f32_sqrt', operation)
      when :f64_sqrt then emit_fp_unary('f64_sqrt', operation)
      # Floating point fused operations
      when :f32_mul_add then emit_fp_ternary('f32_mulAdd', operation)
      when :f64_mul_add then emit_fp_ternary('f64_mulAdd', operation)
      when :f32_mul_sub
        dst, src1, src2, src3 = map_n_operands(operation, 4)
        @emitter.emit_line("#{dst} = f32_mulAdd(#{src1}, #{src2}, -#{src3});")
      when :f64_mul_sub
        dst, src1, src2, src3 = map_n_operands(operation, 4)
        @emitter.emit_line("#{dst} = f64_mulAdd(#{src1}, #{src2}, -#{src3});")
      when :f32_mul_sub_n
        dst, src1, src2, src3 = map_n_operands(operation, 4)
        @emitter.emit_line("#{dst} = f32_mulAdd(-#{src1}, #{src2}, -#{src3});")
      when :f64_mul_sub_n
        dst, src1, src2, src3 = map_n_operands(operation, 4)
        @emitter.emit_line("#{dst} = f64_mulAdd(-#{src1}, #{src2}, -#{src3});")
      # Floating point comparison operations
      when :f32_eq then emit_fp_binary('f32_eq', operation)
      when :f64_eq then emit_fp_binary('f64_eq', operation)
      when :f32_lt then emit_fp_binary('f32_lt', operation)
      when :f64_lt then emit_fp_binary('f64_lt', operation)
      when :f32_le then emit_fp_binary('f32_le', operation)
      when :f64_le then emit_fp_binary('f64_le', operation)
      when :f32_min then emit_fp_binary('f32_min', operation)
      when :f64_min then emit_fp_binary('f64_min', operation)
      when :f32_max then emit_fp_binary('f32_max', operation)
      when :f64_max then emit_fp_binary('f64_max', operation)
      # Floating point injections
      when :f32_sign_injection
        dst, src1, src2 = map_n_operands(operation, 3)
        @emitter.emit_line("#{dst} = (#{src1} & 0x7fffffff) | (#{src2} & 0x80000000);")
      when :f64_sign_injection
        dst, src1, src2 = map_n_operands(operation, 3)
        @emitter.emit_line("#{dst} = (#{src1} & 0x7fffffffffffffffULL) | (#{src2} & 0x8000000000000000ULL);")
      when :f32_sign_injection_n
        dst, src1, src2 = map_n_operands(operation, 3)
        @emitter.emit_line("#{dst} = (#{src1} & 0x7fffffff) | (~#{src2} & 0x80000000);")
      when :f64_sign_injection_n
        dst, src1, src2 = map_n_operands(operation, 3)
        @emitter.emit_line("#{dst} = (#{src1} & 0x7fffffffffffffffULL) | (~#{src2} & 0x8000000000000000ULL);")
      when :f32_sign_xor
        dst, src1, src2 = map_n_operands(operation, 3)
        @emitter.emit_line("#{dst} = #{src1} ^ (#{src2} & 0x80000000);")
      when :f64_sign_xor
        dst, src1, src2 = map_n_operands(operation, 3)
        @emitter.emit_line("#{dst} = #{src1} ^ (#{src2} & 0x8000000000000000ULL);")
      # Floating point conversions
      when :f32_to_i32 then emit_fp_unary('f32_to_i32', operation)
      when :f32_to_u32 then emit_fp_unary('f32_to_ui32', operation)
      when :f32_to_i64 then emit_fp_unary('f32_to_i64', operation)
      when :f32_to_u64 then emit_fp_unary('f32_to_ui64', operation)
      when :i32_to_f32 then emit_fp_unary('i32_to_f32', operation)
      when :u32_to_f32 then emit_fp_unary('ui32_to_f32', operation)
      when :i64_to_f32 then emit_fp_unary('i64_to_f32', operation)
      when :u64_to_f32 then emit_fp_unary('ui64_to_f32', operation)
      # Classification
      when :f32_classify
        dst, src = map_n_operands(operation, 2)

        @emitter.emit_line('{')
        @emitter.emit_line("uint32_t _v = #{src};")
        @emitter.emit_line('uint32_t _sign = _v >> 31;')
        @emitter.emit_line('uint32_t _exp  = (_v >> 23) & 0xFF;')
        @emitter.emit_line('uint32_t _frac = _v & 0x7FFFFF;')
        @emitter.emit_line('')
        @emitter.emit_line('if (_exp == 0xFF) {')
        @emitter.emit_line("  if (_frac == 0) { #{dst} = _sign ? (1u << 0) : (1u << 7); }")
        @emitter.emit_line("  else if (_frac & (1u << 22)) { #{dst} = (1u << 9); }")
        @emitter.emit_line("  else { #{dst} = (1u << 8); }")
        @emitter.emit_line('}')
        @emitter.emit_line('else if (_exp == 0) {')
        @emitter.emit_line("  if (_frac == 0) { #{dst} = _sign ? (1u << 3) : (1u << 4); }")
        @emitter.emit_line("  else { #{dst} = _sign ? (1u << 2) : (1u << 5); }")
        @emitter.emit_line('}')
        @emitter.emit_line('else {')
        @emitter.emit_line("  #{dst} = _sign ? (1u << 1) : (1u << 6);")
        @emitter.emit_line('}')
        @emitter.emit_line('}')

      when :f64_classify
        dst, src = map_n_operands(operation, 2)
        @emitter.emit_line('{')
        @emitter.emit_line("uint64_t v = #{src};")
        @emitter.emit_line('uint64_t sign = v >> 63;')
        @emitter.emit_line('uint64_t exp  = (v >> 52) & 0x7FF;')
        @emitter.emit_line('uint64_t frac = v & 0xFFFFFFFFFFFFFULL;')
        @emitter.emit_line('uint32_t r = 0;')
        @emitter.emit_line('')
        @emitter.emit_line('if (exp == 0x7FF) {')
        @emitter.emit_line('  if (frac == 0) r = sign ? (1u << 0) : (1u << 7);')
        @emitter.emit_line('  else r = (frac & (1ULL << 51)) ? (1u << 9) : (1u << 8);')
        @emitter.emit_line('}')
        @emitter.emit_line('else if (exp == 0) {')
        @emitter.emit_line('  if (frac == 0) r = sign ? (1u << 3) : (1u << 4);')
        @emitter.emit_line('  else r = sign ? (1u << 2) : (1u << 5);')
        @emitter.emit_line('}')
        @emitter.emit_line('else {')
        @emitter.emit_line('  r = sign ? (1u << 1) : (1u << 6);')
        @emitter.emit_line('}')
        @emitter.emit_line('')
        @emitter.emit_line("#{dst} = r;")
        @emitter.emit_line('}')

      else raise 'Unknown statement type, terminating program'
      end
    end
  end
end
