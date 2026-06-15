# lira/lira_gen.rb
#!/usr/bin/env ruby

require_relative 'ADL/base'
require_relative 'ADL/builder'
require_relative 'lira/arch'
require_relative 'lira/ir'
require_relative 'lira/ir_builder'
require_relative 'lira/ir_ops'
require_relative 'lira/arch_ser_yaml'
require_relative 'lira/ir_ser_txt'
require_relative 'Utility/lira_utils'

class LiraSerializer
  def initialize(arch_name, arch_attributes = [])
    @arch_name = arch_name
    @arch_attributes = arch_attributes
    @arch_builder = nil
    @builder = nil
    @vars = nil
    @operand_names = nil
    @operand_vars = nil

    @decode_cache = {}
    @decode_snip_id = 0

    # NOTE: Temporary disabled
    # @encode_cache = {}
    # @encode_snip_id = 0
  end

  def process_binary_op(name, oprnds)
    a = ADLToLiraUtils.resolve_operand(oprnds[1], @builder, @vars, @operand_names, @arch_builder)
    b = ADLToLiraUtils.resolve_operand(oprnds[2], @builder, @vars, @operand_names, @arch_builder)
    return nil if a.nil? || b.nil?
    out = ADLToLiraUtils.binary_op(@builder, name, oprnds[1].type, a, b)
    @vars[oprnds[0]] = out
    out
  end

  def process_cmp_op(name, oprnds)
    a = ADLToLiraUtils.resolve_operand(oprnds[1], @builder, @vars, @operand_names, @arch_builder)
    b = ADLToLiraUtils.resolve_operand(oprnds[2], @builder, @vars, @operand_names, @arch_builder)
    return nil if a.nil? || b.nil?
    unsigned = oprnds[1].type.to_s.start_with?('u')
    out = ADLToLiraUtils.cmp_op(@builder, name, a, b, unsigned)
    @vars[oprnds[0]] = out
    out
  end

  def process_rem(oprnds)
    a = ADLToLiraUtils.resolve_operand(oprnds[1], @builder, @vars, @operand_names, @arch_builder)
    b = ADLToLiraUtils.resolve_operand(oprnds[2], @builder, @vars, @operand_names, @arch_builder)
    return nil if a.nil? || b.nil?
    unsigned = oprnds[1].type.to_s.start_with?('u')
    out = ADLToLiraUtils.rem_op(@builder, a, b, unsigned)
    @vars[oprnds[0]] = out
    out
  end

  def process_div(oprnds)
    a = ADLToLiraUtils.resolve_operand(oprnds[1], @builder, @vars, @operand_names, @arch_builder)
    b = ADLToLiraUtils.resolve_operand(oprnds[2], @builder, @vars, @operand_names, @arch_builder)
    return nil if a.nil? || b.nil?
    unsigned = oprnds[1].type.to_s.start_with?('u')
    out = ADLToLiraUtils.div_op(@builder, a, b, unsigned)
    @vars[oprnds[0]] = out
    out
  end

  def find_register_file(name)
    @arch_builder.register_files.find { |rf| rf.name == name }
  end

  def process_read_reg(oprnds)
    reg_var = oprnds[1]
    idx = @operand_names.index(reg_var.name.to_s)
    if idx
      reg_num = @builder.input(idx, ADLToLiraUtils.convert_type(reg_var.type))
      rf_name = reg_var.regset.to_s
      rf = find_register_file(rf_name)
      if rf.nil?
        warn "Register file '#{rf_name}' not found, skipping statement"
        return nil
      end
      out = @builder.read(rf, reg_num)
      @vars[oprnds[0]] = out
      out
    else
      # Special Registers (PC)
      val = ADLToLiraUtils.resolve_operand(reg_var, @builder, @vars, @operand_names, @arch_builder)
      @vars[oprnds[0]] = val if val
      val
    end
  end

  def process_write_reg(oprnds)
    reg_var = oprnds[0]
    val = ADLToLiraUtils.resolve_operand(oprnds[1], @builder, @vars, @operand_names, @arch_builder)
    return nil if val.nil?
    idx = @operand_names.index(reg_var.name.to_s)
    if idx
      reg_num = @builder.input(idx, ADLToLiraUtils.convert_type(reg_var.type))
      rf_name = reg_var.regset.to_s
      rf = find_register_file(rf_name)
      if rf.nil?
        warn "Register file '#{rf_name}' not found, skipping statement"
        return nil
      end
      @builder.write(rf, reg_num, val)
    elsif ADLToLiraUtils::SPECIAL_REGS.include?(reg_var.name.to_s)
      ef = ADLToLiraUtils.find_env_func(@arch_builder, "setPC", [32], [])
      if ef.nil?
        warn "Environment function 'setPC' not registered, skipping statement"
        return nil
      end
      @builder.env(ef, [val])
    else
      warn "Register file '#{rf_name}' not found, skipping statement"
    end
    nil
  end

  def process_read_mem(name, oprnds)
    out_type = ADLToLiraUtils.convert_type(oprnds[0].type)
    addr = ADLToLiraUtils.resolve_operand(oprnds[1], @builder, @vars, @operand_names, @arch_builder)
    return nil if addr.nil?
    addr_width = addr.width
    ef = ADLToLiraUtils.find_env_func(@arch_builder, name.to_s, [addr_width], [out_type])
    if ef.nil?
      warn "Environment function #{name} wasn't registered, skipping statement"
      return nil
    end
    outs = @builder.env(ef, [addr])
    out = outs[0]
    @vars[oprnds[0]] = out
    out
  end

  def process_write_mem(name, oprnds)
    addr = ADLToLiraUtils.resolve_operand(oprnds[0], @builder, @vars, @operand_names, @arch_builder)
    val = ADLToLiraUtils.resolve_operand(oprnds[1], @builder, @vars, @operand_names, @arch_builder)
    return nil if addr.nil? || val.nil?
    addr_width = addr.width
    ef = ADLToLiraUtils.find_env_func(@arch_builder, name.to_s, [addr_width, val.width], [])
    if ef.nil?
      warn "Environment function #{name} wasn't registered, skipping statement"
      return nil
    end
    @builder.env(ef, [addr, val])
    nil
  end

  def process_extract(oprnds)
    val = ADLToLiraUtils.resolve_operand(oprnds[1], @builder, @vars, @operand_names, @arch_builder)
    return nil if val.nil?
    hi = oprnds[2].value
    lo = oprnds[3].value
    width = hi - lo + 1
    width = 1 if width < 1
    out = @builder.extract(val, @builder.const(lo, 32), width)
    @vars[oprnds[0]] = out
    out
  end

  def process_cast_zext(name, oprnds)
    dest_type = oprnds[0].type
    dest_width = ADLToLiraUtils.convert_type(dest_type)
    dest_width = 1 if dest_width < 1
    src = ADLToLiraUtils.resolve_operand(oprnds[1], @builder, @vars, @operand_names, @arch_builder)
    return nil if src.nil?
    # Truncate if src is wider than the expected source type
    src_expected_width = ADLToLiraUtils.convert_type(oprnds[1].type)
    if src.width > src_expected_width
      src = @builder.extract_low(src, src_expected_width)
    end
    if src.width == dest_width
      out = src
    else
      if name == :zext || dest_type.to_s.start_with?('u')
        out = @builder.extend_zero(src, dest_width)
      else
        out = @builder.extend_sign(src, dest_width)
      end
    end
    @vars[oprnds[0]] = out
    out
  end

  def stmt_to_lira(stmt)
    name = stmt.name
    oprnds = stmt.oprnds

    case name
    when :new_var
      var = oprnds[0]
      width = ADLToLiraUtils.convert_type(var.type)
      width = 1 if width < 1
      val = @builder.seq.new_temp(width)
      @vars[var] = val

    when :let
      lhs, rhs = oprnds
      rhs_val = ADLToLiraUtils.resolve_operand(rhs, @builder, @vars, @operand_names, @arch_builder)
      @vars[lhs] = rhs_val if rhs_val

    when :add, :sub, :mul, :and, :or, :xor, :shl, :shr, :ashr
      out = process_binary_op(name, oprnds)
      @vars[oprnds[0]] = out if out

    when :lt, :gt, :le, :ge, :eq, :ne
      out = process_cmp_op(name, oprnds)
      @vars[oprnds[0]] = out if out

    when :select
      cond = ADLToLiraUtils.resolve_operand(oprnds[1], @builder, @vars, @operand_names, @arch_builder)
      t = ADLToLiraUtils.resolve_operand(oprnds[2], @builder, @vars, @operand_names, @arch_builder)
      f = ADLToLiraUtils.resolve_operand(oprnds[3], @builder, @vars, @operand_names, @arch_builder)
      return if cond.nil? || t.nil? || f.nil?
      cond = ADLToLiraUtils.ensure_width(cond, 1, @builder)
      out = @builder.select(cond, t, f)
      @vars[oprnds[0]] = out

    when :extract
      process_extract(oprnds)

    when :cast, :zext
      process_cast_zext(name, oprnds)

    when :readReg
      process_read_reg(oprnds)

    when :writeReg
      process_write_reg(oprnds)

    when :readMem
      process_read_mem(stmt.attrs, oprnds)

    when :writeMem
      process_write_mem(stmt.attrs, oprnds)

    when :branch
      target = ADLToLiraUtils.resolve_operand(oprnds[0], @builder, @vars, @operand_names, @arch_builder)
      return if target.nil?
      ef = ADLToLiraUtils.find_env_func(@arch_builder, "setPC", [32], [])
      if ef.nil?
        warn "Environment function 'setPC' not registered, skipping statement"
        return
      end
      @builder.env(ef, [target])

    when :sysCall
      ef = ADLToLiraUtils.find_env_func(@arch_builder, "sysCall", [], [])
      if ef.nil?
        warn "Environment function 'sysCall' not registered, skipping statement"
        return
      end
      @builder.env(ef, [])

    when :rem
      process_rem(oprnds)

    when :div
      process_div(oprnds)

    else
      raise "Unhandled statement: #{name}"
    end
  end

  def generate_semantic(instr)
    return Lira::StatementSeq.new([]) if instr.code.tree.empty?

    @builder = Lira::InstructionBuilder.new(
      instr.name.to_s, [], [],
      Lira::InstructionEncoding.new(32, 0, 0, [], '', '', '')
    )
    @vars = {}
    @operand_names = collect_operand_names(instr)
    instr.code.tree.each do |stmt|
      stmt_to_lira(stmt)
    end
    @builder.seq.build
  end

  def generate_decode_snippets(instr, operand_vars)
    decode_snippet_names = []
    @builder = Lira::SnippetBuilder.new("temp_decode")
    @vars = {}
    enc = @builder.input(0, 32)

    instr.map.tree.each do |stmt|
      name = stmt.name
      oprnds = stmt.oprnds

      case name
      when :new_var
        v = oprnds[0]
        width = ADLToLiraUtils.convert_type(v.type)
        width = 1 if width < 1
        val = @builder.seq.new_temp(width)
        @vars[v] = val

      when :let
        lhs, rhs = oprnds
        if rhs.is_a?(SimInfra::Var) && rhs.name.to_s.start_with?('f_')
          field_name = rhs.name.to_s[2..-1]
          field = instr.fields.find { |f| f.value.name.to_s == "f_#{field_name}" }
          if field
            val = ADLToLiraUtils.extract_field(@builder, enc, field, lhs.type)
            @vars[lhs] = val
          else
            warn "Field #{field_name} not found"
          end
        else
          rhs_val = ADLToLiraUtils.resolve_operand(rhs, @builder, @vars, [], @arch_builder)
          @vars[lhs] = rhs_val if rhs_val
        end

      when :cast, :zext
        lhs, rhs = oprnds
        src = @vars[rhs]
        if src
          dest_type = lhs.type
          dest_width = ADLToLiraUtils.convert_type(dest_type)
          dest_width = 1 if dest_width < 1
          src_expected_width = ADLToLiraUtils.convert_type(rhs.type)
          if src.width > src_expected_width
            src = @builder.extract_low(src, src_expected_width)
          end
          if src.width == dest_width
            val = src
          else
            if name == :zext || dest_type.to_s.start_with?('u')
              val = @builder.extend_zero(src, dest_width)
            else
              val = @builder.extend_sign(src, dest_width)
            end
          end
          @vars[lhs] = val
        elsif rhs.is_a?(SimInfra::Var) && rhs.name.to_s.start_with?('f_')
          field_name = rhs.name.to_s[2..-1]
          field = instr.fields.find { |f| f.value.name.to_s == "f_#{field_name}" }
          if field
            val = ADLToLiraUtils.extract_field(@builder, enc, field, lhs.type)
            @vars[lhs] = val
          else
            warn "Field #{field_name} not found"
          end
        else
          rhs_val = ADLToLiraUtils.resolve_operand(rhs, @builder, @vars, [], @arch_builder)
          @vars[lhs] = rhs_val if rhs_val
        end

      when :add, :sub, :mul, :and, :or, :xor, :shl, :shr, :ashr
        out = process_binary_op(name, oprnds)
        @vars[oprnds[0]] = out if out

      when :lt, :gt, :le, :ge, :eq, :ne
        out = process_cmp_op(name, oprnds)
        @vars[oprnds[0]] = out if out

      else
        # Ignore other statements in decode snippet
      end
    end

    operand_vars.each_with_index do |var, idx|
      val = @vars[var]
      @builder.output(val || @builder.const(0, 32), idx)
    end

    snippet = @builder.build
    seq_str = Lira::IrSerTxt.serialize_statement_seq(snippet.seq)

    if @decode_cache.key?(seq_str)
      decode_snippet_names << @decode_cache[seq_str]
    else
      unique_name = "decode_#{@decode_snip_id}"
      snippet.name = unique_name
      @arch_builder.add_snippet(snippet)
      @decode_snip_id += 1
      @decode_cache[seq_str] = unique_name
      decode_snippet_names << unique_name
    end
    decode_snippet_names
  end


  # NOTE: Temporary disabled
  # def generate_encode_snippet(instr, operand_vars)
  #   @builder = Lira::SnippetBuilder.new("temp_encode")
  #
  #   operand_values = operand_vars.each_with_index.map do |var, idx|
  #     width = ADLToLiraUtils.convert_type(var.type)
  #     width = 1 if width < 1
  #     @builder.input(idx, width)
  #   end
  #
  #   base = @builder.const(0, 32)
  #   instr.fields.each do |field|
  #     lo = field.from
  #     hi = field.to
  #     width = hi - lo + 1
  #     width = 1 if width < 1
  #     field_var_name = field.value.name.to_s
  #     value_num = field.value.value
  #     if value_num
  #       const_val = @builder.const(value_num, width)
  #       const_val = ADLToLiraUtils.ensure_width(const_val, 32, @builder)
  #       shifted = @builder.lsl(const_val, @builder.const(lo, 32))
  #       base = @builder.orr(base, shifted)
  #     elsif field_var_name =~ /^f_(.+)$/
  #       operand_name = $1
  #       idx = operand_vars.index { |v| v.name.to_s == operand_name }
  #       if idx
  #         op_val = operand_values[idx]
  #         op_val = ADLToLiraUtils.ensure_width(op_val, 32, @builder)
  #         shifted = @builder.lsl(op_val, @builder.const(lo, 32))
  #         base = @builder.orr(base, shifted)
  #       end
  #     end
  #   end
  #
  #   @builder.output(base, 0)
  #   snippet = @builder.build
  #   seq_str = Lira::IrSerTxt.serialize_statement_seq(snippet.seq)
  #   if @encode_cache.key?(seq_str)
  #     return @encode_cache[seq_str]
  #   else
  #     unique_name = "encode_#{@encode_snip_id}"
  #     snippet.name = unique_name
  #     @arch_builder.add_snippet(snippet)
  #     @encode_snip_id += 1
  #     @encode_cache[seq_str] = unique_name
  #     unique_name
  #   end
  # end

  def collect_operand_vars(instr)
    operand_vars = []
    instr.map.tree.each do |stmt|
      if stmt.name == :new_var
        var = stmt.oprnds[0]
        attrs = stmt.attrs
        operand_vars << var if attrs && attrs.include?(:op)
      end
    end
    operand_vars
  end

  def collect_operand_names(instr)
    collect_operand_vars(instr).map { |v| v.name.to_s }
  end

  def convert_instruction(instr)
    operand_vars = collect_operand_vars(instr)
    operand_names = collect_operand_names(instr)
    @operand_names = operand_names
    semantic = generate_semantic(instr)

    decode_snippets = []
    encode_snippet = nil
    if instr.map.tree.any? && operand_vars.any?
      decode_snippets = generate_decode_snippets(instr, operand_vars)
    end
    # if instr.fields.any? && operand_vars.any?
    #   encode_snippet = generate_encode_snippet(instr, operand_vars)
    # end

    const_part = 0
    const_mask = 0
    instr.fields.each do |field|
      value_num = field.value.value
      low_bit = field.to
      high_bit = field.from
      width = high_bit - low_bit + 1
      if !value_num.nil?
        const_part |= (value_num << low_bit)
        const_mask |= (((1 << width) - 1) << low_bit)
      end
    end

    operand_sizes = operand_vars.map { |v| ADLToLiraUtils.convert_type(v.type) }

    encoding = Lira::InstructionEncoding.new(32, const_part, const_mask, decode_snippets, '', '', '')
    Lira::Instruction.new(instr.name.to_s, [], operand_sizes, operand_names, encoding, semantic)
  end

  def build_arch
    @arch_builder = Lira::ArchBuilder.new(@arch_name, @arch_attributes)

    SimInfra.class_variable_get(:@@regfiles).each do |rf|
      regs = rf.regs.map do |reg|
        attrs = reg.attrs.map(&:to_s)
        Lira::Register.new(reg.name.to_s, attrs)
      end
      lira_rf = Lira::RegisterFile.new(rf.name.to_s, [], Lira::Shape.new(32, nil), regs)
      @arch_builder.add_register_file(lira_rf)
    end

    env_funcs = SimInfra.interface_functions.dup
    env_funcs.uniq! { |f| [f[:name], f[:return_types], f[:argument_types]] }
    env_funcs.each do |ef|
      inputs = ef[:argument_types].map { |t| ADLToLiraUtils.convert_type(t) }
      outputs = ef[:return_types].map { |t| ADLToLiraUtils.convert_type(t) }
      lira_ef = Lira::EnvironmentFunction.new(ef[:name].to_s, [], inputs, outputs)
      @arch_builder.add_env_func(lira_ef)
    end

    @arch_builder.add_env_func(Lira::EnvironmentFunction.new("getPC", [], [], [32]))
    @arch_builder.add_env_func(Lira::EnvironmentFunction.new("setPC", [], [32], []))

    SimInfra.class_variable_get(:@@instructions).each do |instr|
      begin
        lira_instr = convert_instruction(instr)
        @arch_builder.add_instruction(lira_instr)
      rescue => e
        warn "Skipping #{instr.name}: #{e}"
      end
    end

    @arch_builder.build
  end
end

require 'optparse'
require 'pathname'

def load_target(path)
  target_path = Pathname.new(path)
  if target_path.directory?
    Dir.glob(target_path.join('*.rb')).sort.each do |file|
      require_relative file
    end
  elsif target_path.file? && target_path.extname == '.rb'
    require_relative target_path
  else
    warn "Target '#{path}' is neither a directory nor a .rb file"
    exit 1
  end
end

def extract_arch_name(loaded_modules)
  target_name = nil
  ObjectSpace.each_object(Module) do |mod|
    if mod.is_a?(Module) && mod.name && mod.name !~ /^SimInfra/ && mod.constants.include?(:XRegs)
      target_name = mod.name.to_s
      break
    end
  end
  target_name ||= "TargetArch"
  [target_name, []]
end

def main
  options = {
    output: 'lira.yaml',
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"
    opts.on('-o', '--output FILE', 'Output YAML file (default: lira.yaml)') do |f|
      options[:output] = f
    end
    opts.on('-t', '--target PATH', 'Target architecture directory or .rb file') do |p|
      options[:target] = p
    end
    opts.on('-h', '--help', 'Show this help') do
      puts opts
      exit
    end
  end.parse!

  load_target(options[:target])

  arch_name, arch_attrs = extract_arch_name(nil)
  serializer = LiraSerializer.new(arch_name, arch_attrs)
  arch = serializer.build_arch
  Lira::ArchSerYaml.write_arch(arch, options[:output])
  puts "Serialized architecture to #{options[:output]}"
end

if __FILE__ == $0
  main
end
