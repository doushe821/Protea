require_relative '../lib/lira/ir'
require_relative '../lib/Utility/helper_cpp'

module LiraCppGen
  class Translator
    def initialize(seq, context = :execute, indent = 0)
      @seq = seq
      @context = context
      @indent = indent
      @output = []
      @var_widths = {}
    end

    def translate
      @seq.stmts.each { |stmt| translate_stmt(stmt) }
      @output.join("\n")
    end

    private

    def resolve_var(name, stmt = nil)
      return name if @var_widths.key?(name)
      if name =~ /^_t\d+$/
        width = 32
        if stmt && stmt.respond_to?(:outputs_types) && stmt.outputs_types.any?
          width = stmt.outputs_types[0]
        end
        emit("#{Utility::HelperCpp.gen_type(width)} #{name} = 0;")
        @var_widths[name] = width
        return name
      end
      raise "Unknown variable #{name} in #{stmt&.inspect}"
    end

    def translate_stmt(stmt)
      case stmt.kind
      when 'op'        then translate_op(stmt)
      when 'const'     then translate_const(stmt)
      when 'dyn_const' then translate_dyn_const(stmt)
      when 'read'      then translate_read(stmt)
      when 'write'     then translate_write(stmt)
      when 'env'       then translate_env(stmt)
      when 'cond_env'  then translate_cond_env(stmt)
      when 'input'     then translate_input(stmt)
      when 'output'    then translate_output(stmt)
      else raise "Unknown statement kind: #{stmt.kind}"
      end
    end

    def translate_op(stmt)
      op_full = stmt.specifier
      out = stmt.outputs[0]
      out_width = stmt.outputs_types[0]
      inputs = stmt.inputs.map { |i| resolve_var(i, stmt) }

      unless @var_widths.key?(out)
        emit("#{Utility::HelperCpp.gen_type(out_width)} #{out};")
        @var_widths[out] = out_width
      end

      base_op = op_full.sub(/_\d+$/, '')

      if ['div_u', 'div_s', 'divs', 'divu'].include?(base_op)
        func = base_op == 'divs' ? 'div_s' : (base_op == 'divu' ? 'div_u' : base_op)
        func = "#{func}_#{out_width}"
        emit("#{out} = #{func}(#{inputs[0]}, #{inputs[1]}, #{inputs[2]});")
        return
      end

      case base_op
      when 'select'
        emit("#{out} = #{inputs[0]} ? #{inputs[1]} : #{inputs[2]};")
      when 'extract_low'
        emit("#{out} = extract_low_#{out_width}(#{inputs[0]});")
      when 'extend_sign', 'extend_zero'
        in_width = @var_widths[inputs[0]] || 1
        func = "#{base_op}_#{in_width}_#{out_width}"
        emit("#{out} = #{func}(#{inputs[0]});")
      else
        if out_width == 1 && ['eq','ne','slt','sle','sgt','sge','ult','ule','ugt','uge'].include?(base_op)
          a, b = inputs
          func = "#{base_op}_32"
          emit("#{out} = #{func}(#{a}, #{b});")
          return
        end

        func_name = base_op
        if base_op == 'rem'
          func_name = 'rem_s'
        elsif base_op == 'rems'
          func_name = 'rem_s'
        elsif base_op == 'remu'
          func_name = 'rem_u'
        end
        func = "#{func_name}_#{out_width}"
        if inputs.size == 1
          emit("#{out} = #{func}(#{inputs[0]});")
        elsif inputs.size == 2
          emit("#{out} = #{func}(#{inputs[0]}, #{inputs[1]});")
        else
          raise "Unsupported arity for #{base_op} (#{inputs.size} args)"
        end
      end
    end

    def translate_const(stmt)
      value = stmt.specifier
      out = stmt.outputs[0]
      width = stmt.outputs_types[0]
      unless @var_widths.key?(out)
        emit("#{Utility::HelperCpp.gen_type(width)} #{out} = #{value};")
        @var_widths[out] = width
      end
    end

    def translate_dyn_const(stmt)
      name = stmt.specifier
      out = stmt.outputs[0]
      width = stmt.outputs_types[0]
      unless @var_widths.key?(out)
        emit("#{Utility::HelperCpp.gen_type(width)} #{out} = #{name};")
        @var_widths[out] = width
      end
    end

    def translate_read(stmt)
      rf = stmt.specifier
      idx = resolve_var(stmt.inputs[0], stmt)
      out = stmt.outputs[0]
      width = stmt.outputs_types[0]
      unless @var_widths.key?(out)
        emit("#{Utility::HelperCpp.gen_type(width)} #{out};")
        @var_widths[out] = width
      end
      if @context == :execute
        emit("#{out} = cpu.get#{rf}<#{Utility::HelperCpp.gen_type(width)}>(#{idx});")
      else
        emit("#{out} = 0; // read in decode")
      end
    end

    def translate_write(stmt)
      rf = stmt.specifier
      idx = resolve_var(stmt.inputs[0], stmt)
      val = resolve_var(stmt.inputs[1], stmt)
      if @context == :execute
        emit("cpu.set#{rf}(#{idx}, #{val});")
      end
    end


    def translate_env(stmt)
      func = stmt.specifier
      inputs = stmt.inputs.map { |i| resolve_var(i, stmt) }
      outputs = stmt.outputs
      out_types = stmt.outputs_types

      if func == 'readMem' && out_types.size == 1
        func = "readMem#{out_types[0]}"
      elsif func == 'writeMem' && inputs.size == 2
        val_name = stmt.inputs[1]
        width = @var_widths[val_name] || 32
        func = "writeMem#{width}"
      end

      if @context == :execute
        if outputs.empty?
          emit("cpu.#{func}(#{inputs.join(', ')});")
        else
          if outputs.size == 1
            out = outputs[0]
            width = out_types[0]
            unless @var_widths.key?(out)
              emit("#{Utility::HelperCpp.gen_type(width)} #{out};")
              @var_widths[out] = width
            end
            emit("#{out} = cpu.#{func}(#{inputs.join(', ')});")
          else
            outputs.each_with_index do |out, i|
              width = out_types[i]
              unless @var_widths.key?(out)
                emit("#{Utility::HelperCpp.gen_type(width)} #{out};")
                @var_widths[out] = width
              end
            end
            emit("std::tie(#{outputs.join(', ')}) = cpu.#{func}(#{inputs.join(', ')});")
          end
        end
      end
    end

    def translate_cond_env(stmt)
      cond = resolve_var(stmt.inputs[0], stmt)
      inputs = stmt.inputs[1...-stmt.outputs.size].map { |i| resolve_var(i, stmt) }
      on_false = stmt.inputs[-stmt.outputs.size..-1].map { |i| resolve_var(i, stmt) }
      func = stmt.specifier
      outputs = stmt.outputs
      emit("if (#{cond}) {")
      indent do
        outputs.each_with_index do |out, i|
          width = stmt.outputs_types[i]
          unless @var_widths.key?(out)
            emit("#{Utility::HelperCpp.gen_type(width)} #{out};")
            @var_widths[out] = width
          end
          emit("#{out} = cpu.#{func}(#{inputs.join(', ')});")
        end
      end
      emit("} else {")
      indent do
        outputs.each_with_index do |out, i|
          emit("#{out} = #{on_false[i]};")
        end
      end
      emit("}")
    end

    def translate_input(stmt)
      idx = stmt.specifier.to_i
      out = stmt.outputs[0]
      width = stmt.outputs_types[0]
      unless @var_widths.key?(out)
        emit("#{Utility::HelperCpp.gen_type(width)} #{out};")
        @var_widths[out] = width
      end
      if @context == :decode
        emit("#{out} = raw_insn;")
      else
        emit("#{out} = insn.operand#{idx};")
      end
    end

    def translate_output(stmt)
      val = resolve_var(stmt.inputs[0], stmt)
      idx = stmt.specifier.to_i
      emit("insn.operand#{idx} = #{val};")
    end

    def emit(line)
      @output << (" " * @indent + line)
    end

    def indent
      @indent += 2
      yield
      @indent -= 2
    end
  end
end
