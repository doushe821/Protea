require 'Utility/helper_cpp'
require 'Utility/fp_helper_cpp'
# frozen_string_literal: true

# Semantics Generator: Converts IR to C++ code
module CodeGen
  class CppGenerator
    attr_reader :emitter, :mapping

    # PROPOSAL:
    # Add RM (rounding modes) map that converts
    # RV rounding modes into softfloat rounding modes.
    # They actually are exactly the same, but we can generalize this idea later.
    # Maybe should move it to other module
    # RISC-V RM to SoftFloat RM mapping
    # RNE=0 -> softfloat_round_near_even(0), RTZ=1 -> softfloat_round_minMag(1),
    # RDN=2 -> softfloat_round_min(2), RUP=3 -> softfloat_round_max(3),
    # RMM=4 -> softfloat_round_near_maxMag(4), DYN=7 -> read from fcsr
    SOFTFLOAT_RM_MAP = {
      0 => 'softfloat_round_near_even',
      1 => 'softfloat_round_minMag',
      2 => 'softfloat_round_min',
      3 => 'softfloat_round_max',
      4 => 'softfloat_round_near_maxMag',
      7 => nil # DYN - handled specially
    }.freeze

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

    # PROPOSAL:
    # Add FP emitter helpers
    # Emit code to set SoftFloat rounding mode before FP operation
    # For most instruction in softfloat, rounding mode is defined
    # by global variable, so we have to change it before we execute.
    # We also store it into a temporal variable, so we can restore it later.
    def emit_rm_setup(rm, tmp_var = '_rm_save')
      return unless rm # nil means no rm handling needed

      # Currently not supported
      if rm == 7 # DYN mode - read from fcsr at runtime
        @emitter.emit_line('assert(0 && "CSR is currently not supported\n");')
        @emitter.emit_line("uint_fast8_t #{tmp_var} = softfloat_roundingMode;")
        # @emitter.emit_line('softfloat_roundingMode = cpu.getFCSR_RM();')
      else
        rm_const = SOFTFLOAT_RM_MAP[rm]
        @emitter.emit_line("uint_fast8_t #{tmp_var} = softfloat_roundingMode;")
        @emitter.emit_line("softfloat_roundingMode = #{rm_const};")
      end
    end

    # Emit code to restore SoftFloat rounding mode after FP operation
    def emit_rm_restore(tmp_var = '_rm_save')
      @emitter.emit_line("softfloat_roundingMode = #{tmp_var};")
    end

    # Emits binary fp operation.
    # This is different from RV32I binop, because:
    # 1. typing is different (check Utility/fp_helper_cpp.rb)
    # 2. Rounding mode has to be changed
    def emit_fp_binary(opname, operation, dst_type:, src_types:, rm: nil)
      dst  = map_operand(operation[:oprnds][0])
      src1 = map_operand(operation[:oprnds][1])
      src2 = map_operand(operation[:oprnds][2])

      t1 = Utility.gen_typed_tmp(src1, src_types[0])
      t2 = Utility.gen_typed_tmp(src2, src_types[1])
      tr = Utility.gen_typed_tmp(dst,  dst_type)

      if Utility::FP_INFO[src_types[0]]
        info = Utility::FP_INFO[src_types[0]]
        @emitter.emit_line("#{info[:c_type]} #{t1} = { #{info[:unpack]}(#{src1}) };")
      else
        ctype = Utility::INT_INFO[src_types[0]]
        @emitter.emit_line("#{ctype} #{t1} = (#{ctype})(#{src1});")
      end

      if Utility::FP_INFO[src_types[1]]
        info = Utility::FP_INFO[src_types[1]]
        @emitter.emit_line("#{info[:c_type]} #{t2} = { #{info[:unpack]}(#{src2}) };")
      else
        ctype = Utility::INT_INFO[src_types[1]]
        @emitter.emit_line("#{ctype} #{t2} = (#{ctype})(#{src2});")
      end

      # Set rounding mode before operation if rm is specified
      emit_rm_setup(rm) if rm

      if Utility::FP_INFO[dst_type]
        ctype = Utility::FP_INFO[dst_type][:c_type]
        @emitter.emit_line("#{ctype} #{tr} = #{opname}(#{t1}, #{t2});")
        pack = Utility::FP_INFO[dst_type][:pack]
        @emitter.emit_line("#{dst} = #{pack % tr};")
      else
        ctype = Utility::INT_INFO[dst_type]
        @emitter.emit_line("#{ctype} #{tr} = #{opname}(#{t1}, #{t2});")
        @emitter.emit_line("#{dst} = (uint64_t)#{tr};")
      end

      # Restore rounding mode after operation if rm was set
      emit_rm_restore if rm
    end

    # float -> int conversions need to be handled separetely, because
    # they break general pattern of softfloat instructions by demanding
    # rounding mode as an argument (they ignore global constant that all other
    # fp functions use for some unknown reason).
    def emit_fp_to_int_conv(opname, operation, dst_type:, src_type:, rounding_mode:, exact: true)
      dst = map_operand(operation[:oprnds][0])
      src = map_operand(operation[:oprnds][1])

      ts = Utility.gen_typed_tmp(src, src_type)
      tr = Utility.gen_typed_tmp(dst, dst_type)

      if Utility::FP_INFO[src_type]
        info = Utility::FP_INFO[src_type]
        @emitter.emit_line("#{info[:c_type]} #{ts} = { #{info[:unpack]}(#{src}) };")
      else
        ctype = Utility::INT_INFO[src_type]
        @emitter.emit_line("#{ctype} #{ts} = (#{ctype})(#{src});")
      end

      exact_arg = exact ? '1' : '0'
      @emitter.emit_line("#{Utility::INT_INFO[dst_type]} #{tr} = #{opname}(#{ts}, #{rounding_mode}, #{exact_arg});")
      @emitter.emit_line("#{dst} = (uint64_t)#{tr};")
    end

    # There is no min/max/neg functions in softfloat,
    # so we have to implement them ourselves
    def emit_fp_min_max(opname, operation, type:)
      dst, src1, src2 = map_n_operands(operation, 3)
      t1 = Utility.gen_typed_tmp(src1, type)
      t2 = Utility.gen_typed_tmp(src2, type)
      tr = Utility.gen_typed_tmp(dst, type)
      info = Utility::FP_INFO[type]
      prefix = type == :f32 ? 'f32' : 'f64'
      sign_bit = type == :f32 ? 31 : 63

      @emitter.emit_line("#{info[:c_type]} #{t1} = { #{info[:unpack]}(#{src1}) };")
      @emitter.emit_line("#{info[:c_type]} #{t2} = { #{info[:unpack]}(#{src2}) };")
      @emitter.emit_line("#{info[:c_type]} #{tr};")

      # Bitwise NaN detection. Couldn't find softfloat's one, also this would faster with JIT
      # in comparison to function call.
      if type == :f32
        @emitter.emit_line("bool _a_nan = ((#{t1}.v >> 23) & 0xFF) == 0xFF && (#{t1}.v & 0x7FFFFF) != 0;")
        @emitter.emit_line("bool _b_nan = ((#{t2}.v >> 23) & 0xFF) == 0xFF && (#{t2}.v & 0x7FFFFF) != 0;")
      else
        @emitter.emit_line("bool _a_nan = ((#{t1}.v >> 52) & 0x7FF) == 0x7FF && (#{t1}.v & 0xFFFFFFFFFFFFF) != 0;")
        @emitter.emit_line("bool _b_nan = ((#{t2}.v >> 52) & 0x7FF) == 0x7FF && (#{t2}.v & 0xFFFFFFFFFFFFF) != 0;")
      end

      is_min = opname.include?('min')

      @emitter.emit_line('{')
      # return number if one of them is NaN, if both are NaN, return second
      @emitter.emit_line("  if (_a_nan && _b_nan) #{tr} = #{t2};")
      @emitter.emit_line("  else if (_a_nan) #{tr} = #{t2};")
      @emitter.emit_line("  else if (_b_nan) #{tr} = #{t1};")
      @emitter.emit_line('  else {')
      if is_min
        # smaller or neg zero
        @emitter.emit_line("    if (#{prefix}_lt(#{t1}, #{t2}) || (#{prefix}_eq(#{t1}, #{t2}) && ((#{t1}.v >> #{sign_bit}) & 1))) #{tr} = #{t1};")
      else
        # larger or pos zero
        @emitter.emit_line("    if (#{prefix}_lt(#{t2}, #{t1}) || (#{prefix}_eq(#{t1}, #{t2}) && ((#{t2}.v >> #{sign_bit}) & 1))) #{tr} = #{t1};")
      end
      @emitter.emit_line("    else #{tr} = #{t2};")
      @emitter.emit_line('  }')
      @emitter.emit_line('}')

      pack = info[:pack]
      @emitter.emit_line("#{dst} = #{pack % tr};")
    end

    def gen_fp_neg(tmp_name, type)
      case type
      when :f32 then "#{tmp_name}.v ^= 0x80000000U;"
      when :f64 then "#{tmp_name}.v ^= 0x8000000000000000ULL;"
      end
    end

    # same as above
    def emit_fp_unary(opname, operation, dst_type:, src_type:, rm: nil)
      dst = map_operand(operation[:oprnds][0])
      src = map_operand(operation[:oprnds][1])

      ts = Utility.gen_typed_tmp(src, src_type)
      tr = Utility.gen_typed_tmp(dst, dst_type)

      if Utility::FP_INFO[src_type]
        info = Utility::FP_INFO[src_type]
        @emitter.emit_line("#{info[:c_type]} #{ts} = { #{info[:unpack]}(#{src}) };")
      else
        ctype = Utility::INT_INFO[src_type]
        @emitter.emit_line("#{ctype} #{ts} = (#{ctype})(#{src});")
      end

      # Set rounding mode before operation if rm is specified
      emit_rm_setup(rm) if rm

      if Utility::FP_INFO[dst_type]
        ctype = Utility::FP_INFO[dst_type][:c_type]
        @emitter.emit_line("#{ctype} #{tr} = #{opname}(#{ts});")
        pack = Utility::FP_INFO[dst_type][:pack]
        @emitter.emit_line("#{dst} = #{pack % tr};")
      else
        ctype = Utility::INT_INFO[dst_type]
        @emitter.emit_line("#{ctype} #{tr} = #{opname}(#{ts});")
        @emitter.emit_line("#{dst} = (uint64_t)#{tr};")
      end

      # Restore rounding mode after operation if rm was set
      emit_rm_restore if rm
    end

    # RV64F has FMA instructions that have 3 sources, so this
    # new emitter is necessary.
    def emit_fp_ternary(opname, operation,
                        dst_type:,
                        src_types:,
                        negate_src: [],
                        rm: nil)
      dst  = map_operand(operation[:oprnds][0])
      src1 = map_operand(operation[:oprnds][1])
      src2 = map_operand(operation[:oprnds][2])
      src3 = map_operand(operation[:oprnds][3])

      srcs  = [src1, src2, src3]
      svars = []

      srcs.each_with_index do |src, i|
        ty = src_types[i]
        t  = Utility.gen_typed_tmp(src, ty)
        svars << t

        if Utility::FP_INFO[ty]
          info = Utility::FP_INFO[ty]
          @emitter.emit_line("#{info[:c_type]} #{t} = { #{info[:unpack]}(#{src}) };")
          if negate_src.include?(i)
            # TODO: change for gen_fp_neg
            negation = gen_fp_neg(t, ty)
            @emitter.emit_line(negation)
            # negf = ty == :f32 ? 'f32_neg' : 'f64_neg'
            # @emitter.emit_line("#{t} = #{negf}(#{t});")
          end

        else
          ctype = Utility::INT_INFO[ty]
          @emitter.emit_line("#{ctype} #{t} = (#{ctype})(#{src});")

          @emitter.emit_line("#{t} = -#{t};") if negate_src.include?(i)
        end
      end

      tr = Utility.gen_typed_tmp(dst, dst_type)

      # Set rounding mode before operation if rm is specified
      emit_rm_setup(rm) if rm

      if Utility::FP_INFO[dst_type]
        ctype = Utility::FP_INFO[dst_type][:c_type]
        @emitter.emit_line("#{ctype} #{tr} = #{opname}(#{svars.join(', ')});")
        pack = Utility::FP_INFO[dst_type][:pack]
        @emitter.emit_line("#{dst} = #{pack % tr};")
      else
        ctype = Utility::INT_INFO[dst_type]
        @emitter.emit_line("#{ctype} #{tr} = #{opname}(#{svars.join(', ')});")
        @emitter.emit_line("#{dst} = (uint64_t)#{tr};")
      end

      # Restore rounding mode after operation if rm was set
      emit_rm_restore if rm
    end

    # No softfloat lib function, so hand-written again
    def emit_sign_inject(operation, width:, mode:)
      dst, src1, src2 = map_n_operands(operation, 3)

      mag_mask, sign_mask =
        if width == 32
          [Utility::F32_MAG_MASK, Utility::F32_SIGN_MASK]
        else
          [Utility::F64_MAG_MASK, Utility::F64_SIGN_MASK]
        end

      sign_expr =
        case mode
        when :copy   then "(#{src2} & #{sign_mask})"
        when :neg    then "(~#{src2} & #{sign_mask})"
        when :xor    then "(#{src1} ^ (#{src2} & #{sign_mask}))"
        end

      result = if mode == :xor
                 sign_expr
               else
                 "(#{src1} & #{mag_mask}) | #{sign_expr}"
               end
      result = "0xFFFFFFFF00000000ULL | (uint64_t)(#{result})" if width == 32
      @emitter.emit_line("#{dst} = #{result};")
    end

    # Helpers for easier operand mapping in operations emitters
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
      # Extract rm from attrs if present.
      rm = operation[:attrs] if operation[:attrs].is_a?(Integer)

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

      # PROPOSAL:
      # Add emitters for RV64F
      # Floating point arithmetic operations WITH rounding mode (SoftFloat global)
      when :f32_add then emit_fp_binary('f32_add', operation,
                                        dst_type: :f32,
                                        src_types: %i[f32 f32],
                                        rm: rm)

      when :f64_add then emit_fp_binary('f64_add', operation,
                                        dst_type: :f64,
                                        src_types: %i[f64 f64],
                                        rm: rm)

      when :f32_sub then emit_fp_binary('f32_sub', operation,
                                        dst_type: :f32,
                                        src_types: %i[f32 f32],
                                        rm: rm)

      when :f64_sub then emit_fp_binary('f64_sub', operation,
                                        dst_type: :f64,
                                        src_types: %i[f64 f64],
                                        rm: rm)

      when :f32_mul then emit_fp_binary('f32_mul', operation,
                                        dst_type: :f32,
                                        src_types: %i[f32 f32],
                                        rm: rm)

      when :f64_mul then emit_fp_binary('f64_mul', operation,
                                        dst_type: :f64,
                                        src_types: %i[f64 f64],
                                        rm: rm)

      when :f32_div then emit_fp_binary('f32_div', operation,
                                        dst_type: :f32,
                                        src_types: %i[f32 f32],
                                        rm: rm)

      when :f64_div then emit_fp_binary('f64_div', operation,
                                        dst_type: :f64,
                                        src_types: %i[f64 f64],
                                        rm: rm)
      when :f32_sqrt then emit_fp_unary('f32_sqrt', operation,
                                        dst_type: :f32,
                                        src_type: :f32,
                                        rm: rm)

      when :f64_sqrt then emit_fp_unary('f64_sqrt', operation,
                                        dst_type: :f64,
                                        src_type: :f64,
                                        rm: rm)
      when :f32_mul_add then emit_fp_ternary('f32_mulAdd', operation,
                                             dst_type: :f32,
                                             src_types: %i[f32 f32 f32],
                                             rm: rm)

      when :f64_mul_add then emit_fp_ternary('f64_mulAdd', operation,
                                             dst_type: :f64,
                                             src_types: %i[f64 f64 f64],
                                             rm: rm)

      # Fused Multiply-Add with Negation
      when :f32_mul_add_n then emit_fp_ternary('f32_mulAdd', operation,
                                               dst_type: :f32,
                                               src_types: %i[f32 f32 f32],
                                               negate_src: [0],
                                               rm: rm)

      when :f64_mul_add_n then emit_fp_ternary('f64_mulAdd', operation,
                                               dst_type: :f64,
                                               src_types: %i[f64 f64 f64],
                                               negate_src: [0],
                                               rm: rm)

      when :f32_mul_sub then emit_fp_ternary('f32_mulAdd', operation,
                                             dst_type: :f32,
                                             src_types: %i[f32 f32 f32],
                                             negate_src: [2],
                                             rm: rm)

      when :f64_mul_sub then emit_fp_ternary('f64_mulAdd', operation,
                                             dst_type: :f64,
                                             src_types: %i[f64 f64 f64],
                                             negate_src: [2],
                                             rm: rm)

      when :f32_mul_sub_n then emit_fp_ternary('f32_mulAdd', operation,
                                               dst_type: :f32,
                                               src_types: %i[f32 f32 f32],
                                               negate_src: [0, 2],
                                               rm: rm)

      when :f64_mul_sub_n then emit_fp_ternary('f64_mulAdd', operation,
                                               dst_type: :f64,
                                               src_types: %i[f64 f64 f64],
                                               negate_src: [0, 2],
                                               rm: rm)

      # Floating point comparisons (no rm)
      when :f32_eq then emit_fp_binary('f32_eq', operation,
                                       dst_type: :i32,
                                       src_types: %i[f32 f32])
      when :f64_eq then emit_fp_binary('f64_eq', operation,
                                       dst_type: :i32,
                                       src_types: %i[f64 f64])
      when :f32_lt then emit_fp_binary('f32_lt', operation,
                                       dst_type: :i32,
                                       src_types: %i[f32 f32])
      when :f64_lt then emit_fp_binary('f64_lt', operation,
                                       dst_type: :i32,
                                       src_types: %i[f64 f64])
      when :f32_le then emit_fp_binary('f32_le', operation,
                                       dst_type: :i32,
                                       src_types: %i[f32 f32])
      when :f64_le then emit_fp_binary('f64_le', operation,
                                       dst_type: :i32,
                                       src_types: %i[f64 f64])

      when :f32_min then emit_fp_min_max('f32_min', operation, type: :f32)
      when :f64_min then emit_fp_min_max('f64_min', operation, type: :f64)
      when :f32_max then emit_fp_min_max('f32_max', operation, type: :f32)
      when :f64_max then emit_fp_min_max('f64_max', operation, type: :f64)

      # Floating point injections
      when :f32_sign_injection   then emit_sign_inject(operation, width: 32, mode: :copy)
      when :f64_sign_injection   then emit_sign_inject(operation, width: 64, mode: :copy)

      when :f32_sign_injection_n then emit_sign_inject(operation, width: 32, mode: :neg)
      when :f64_sign_injection_n then emit_sign_inject(operation, width: 64, mode: :neg)

      when :f32_sign_xor         then emit_sign_inject(operation, width: 32, mode: :xor)
      when :f64_sign_xor         then emit_sign_inject(operation, width: 64, mode: :xor)

      # Floating point conversions with rm
      when :f32_to_i32 then emit_fp_to_int_conv('f32_to_i32', operation, dst_type: :i32, src_type: :f32,
                                                                         rounding_mode: rm)
      when :f32_to_u32 then emit_fp_to_int_conv('f32_to_ui32', operation, dst_type: :u32, src_type: :f32,
                                                                          rounding_mode: rm)
      when :f32_to_i64 then emit_fp_to_int_conv('f32_to_i64', operation, dst_type: :i64, src_type: :f32,
                                                                         rounding_mode: rm)
      when :f32_to_u64 then emit_fp_to_int_conv('f32_to_ui64', operation, dst_type: :u64, src_type: :f32,
                                                                          rounding_mode: rm)

      when :i32_to_f32 then emit_fp_unary('i32_to_f32', operation,
                                          dst_type: :f32, src_type: :i32, rm: rm)

      when :u32_to_f32 then emit_fp_unary('ui32_to_f32', operation,
                                          dst_type: :f32, src_type: :u32, rm: rm)

      when :i64_to_f32 then emit_fp_unary('i64_to_f32', operation,
                                          dst_type: :f32, src_type: :i64, rm: rm)

      when :u64_to_f32 then emit_fp_unary('ui64_to_f32', operation,
                                          dst_type: :f32, src_type: :u64, rm: rm)

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

      else raise "Unknown statement type: #{operation[:name]}, terminating program"
      end
    end
  end
end
