# lira_utils.rb
module ADLToLiraUtils
  OP_MAP = {
    add: :Add,
    sub: :Sub,
    mul: :Mul,
    and: :And,
    or: :Orr,
    xor: :Xor,
    shl: :Lsl,
    shr: :Lsr,
    ashr: :Asr
  }.freeze

  CMP_OP_MAP_S = {
    lt: :Slt,
    gt: :Sgt,
    le: :Sle,
    ge: :Sge,
    eq: :Eq,
    ne: :Ne
  }.freeze

  CMP_OP_MAP_U = {
    lt: :Ult,
    gt: :Ugt,
    le: :Ule,
    ge: :Uge,
    eq: :Eq,
    ne: :Ne
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
end
