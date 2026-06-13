# lira/lira_utils.rb

require_relative '../lira/ir_ops'

module ADLToLiraUtils

  OP_MAP = {
    add: Lira::Add,
    sub: Lira::Sub,
    mul: Lira::Mul,
    and: Lira::And,
    or: Lira::Orr,
    xor: Lira::Xor,
    shl: Lira::Lsl,
    shr: Lira::Lsr,
    ashr: Lira::Asr
  }.freeze

  CMP_OP_MAP_S = {
    eq: Lira::Eq,
    ne: Lira::Ne,
    lt: Lira::Slt,
    gt: Lira::Sgt,
    le: Lira::Sle,
    ge: Lira::Sge
  }.freeze

  CMP_OP_MAP_U = {
    eq: Lira::Eq,
    ne: Lira::Ne,
    lt: Lira::Ult,
    gt: Lira::Ugt,
    le: Lira::Ule,
    ge: Lira::Uge
  }.freeze

  SPECIAL_REGS = %w[pc].freeze

  def self.convert_type(adl_type)
    return 32 if adl_type.nil?
    case adl_type.to_s
    when /^b(\d+)$/ then $1.to_i
    when /^u(\d+)$/, /^s(\d+)$/, /^r(\d+)$/ then $1.to_i
    else 32
    end
  end

  def self.resolve_operand(op, builder, vars, operand_names, arch_builder = nil)
    return nil if op.nil?
    return vars[op] if vars.key?(op)

    if op.is_a?(Integer)
      return builder.const(op, 32)
    end
    if op.is_a?(SimInfra::Constant)
      return builder.const(op.value, 32)
    end
    if op.is_a?(SimInfra::Var)
      width = convert_type(op.type)
      width = 1 if width < 1

      idx = operand_names.index(op.name.to_s)
      if idx
        input_val = builder.input(idx, width)
        vars[op] = input_val

        if op.regset
          rf_name = op.regset.to_s
          rf = arch_builder.register_files.find { |rf| rf.name == rf_name }
          if rf.nil?
            warn "Register file '#{rf_name}' not found, skipping statement"
            return nil
          end
          read_val = builder.seq.new_temp(width)
          builder.read(rf, input_val)
          vars[op] = read_val
          return read_val
        else
          return input_val
        end
      else
        if SPECIAL_REGS.include?(op.name.to_s)
          ef = find_env_func(arch_builder, "getPC", [], [32])
          if ef
            val = builder.env(ef, [])[0]
            vars[op] = val
            return val
          else
            warn "Environment function 'getPC' not registered"
            return nil
          end
        else
          val = builder.seq.new_temp(width)
          vars[op] = val
          return val
        end
      end
    end
    raise "Cannot resolve operand: #{op.inspect}"
  end

  def self.ensure_width(val, width, builder)
    return val if val.width == width
    if val.width < width
      builder.extend_zero(val, width)
    else
      builder.extract_low(val, width)
    end
  end

  def self.find_env_func(arch_builder, name, input_types, output_types)
    arch_builder.environment_functions.find do |ef|
      ef.name == name && ef.inputs == input_types && ef.outputs == output_types
    end
  end

  def self.binary_op(builder, op_name, lhs_type, a, b)
    if op_name == :shr && lhs_type.to_s.start_with?('s')
      op_name = :ashr
    end
    op_class = OP_MAP[op_name]
    target_width = [a.width, b.width].max
    a = ensure_width(a, target_width, builder)
    b = ensure_width(b, target_width, builder)
    out = builder.seq.new_temp(target_width)
    builder.seq.add_op(op_class.new(target_width), [a.name, b.name], [out.name])
    out
  end

  def self.cmp_op(builder, op_name, a, b, unsigned)
    op_map = unsigned ? CMP_OP_MAP_U : CMP_OP_MAP_S
    op_class = op_map[op_name]
    target_width = [a.width, b.width].max
    a = ensure_width(a, target_width, builder)
    b = ensure_width(b, target_width, builder)
    out = builder.seq.new_temp(1)
    builder.seq.add_op(op_class.new(target_width), [a.name, b.name], [out.name])
    out
  end

  def self.rem_op(builder, a, b, unsigned)
    unsigned ? builder.rem_u(a, b) : builder.rem_s(a, b)
  end

  def self.div_op(builder, a, b, unsigned, default = nil)
    default ||= builder.const(0, a.width)
    unsigned ? builder.div_u(a, b, default) : builder.div_s(a, b, default)
  end

  def self.extract_field(builder, enc, field, dest_type)
    low_bit = field.to
    high_bit = field.from
    width = high_bit - low_bit + 1
    shifted = builder.lsr(enc, builder.const(low_bit, 32))
    val = builder.extract_low(shifted, width)
    dest_width = convert_type(dest_type)
    if width != dest_width
      if dest_type.to_s.start_with?('s')
        val = builder.extend_sign(val, dest_width)
      else
        val = builder.extend_zero(val, dest_width)
      end
    end
    val
  end
end
