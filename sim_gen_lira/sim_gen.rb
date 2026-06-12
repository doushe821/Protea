#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.dirname(__FILE__)

require_relative 'cpp_gen'
require_relative 'base_ops_gen'

require_relative 'CPUState/cpu_state'
require_relative 'Decoders/decoder'
require_relative 'ISA/isa'
require_relative 'ExecEngines/naive_interpreter'
require_relative 'ExecEngines/base_exec_engine'
require_relative 'Hart/hart'
require_relative '../lib/lira/arch_ser_yaml'

arch = Lira::ArchSerYaml.read_arch(ARGV[0])

ir_hash = {
  isa_name: arch.name,
  regfiles: arch.register_files.map do |rf|
    {
      name: rf.name,
      regs: rf.regs.map.with_index do |r, idx|
        {
          name: r.name,
          size: rf.reg_size.lanes_base,
          attrs: r.attributes.map(&:to_sym)
        }
      end
    }
  end,
  interface_functions: arch.environment_functions
    .reject { |ef| ['setPC', 'getPC'].include?(ef.name) }
    .map do |ef|
      name = ef.name
      if name == 'readMem' && ef.outputs.size == 1
        name = "readMem#{ef.outputs[0]}"
      elsif name == 'writeMem' && ef.inputs.size == 2
        name = "writeMem#{ef.inputs[1]}"
      end
      { name: name, argument_types: ef.inputs, return_types: ef.outputs }
    end,
  instructions: arch.instructions.map do |insn|
    {
      name: insn.name,
      operand_sizes: insn.operand_sizes,
      operand_names: insn.operand_names,
      encoding: {
        const_part: insn.encoding.const_encoding_part,
        encoded_size: insn.encoding.encoded_size,
        const_mask: insn.encoding.const_mask,
        decode_snippets: insn.encoding.decode
      },
      semantic_seq: insn.semantic
    }
  end,
  snippets: arch.snippets.map { |s| { name: s.name, seq: s.seq } }
}

File.write('cpu_state.hh', SimGen::CPUState::Header.generate_cpu_state(ir_hash))
File.write('cpu_state.cc', SimGen::CPUState::TranslationUnit.generate_cpu_state(ir_hash))
File.write('base_exec_engine.hh', SimGen::BaseExecEngine::Header.generate_base_exec_engine(ir_hash))
File.write('base_exec_engine.cc', SimGen::BaseExecEngine::TranslationUnit.generate_base_exec_engine(ir_hash))
File.write('naive_interpreter.hh', SimGen::NaiveInterpreter::Header.generate_naive_interpreter(ir_hash))
File.write('naive_interpreter.cc', SimGen::NaiveInterpreter::TranslationUnit.generate_naive_interpreter(ir_hash))
File.write('decoder.hh', SimGen::Decoder::Header.generate_decoder(ir_hash))
File.write('decoder.cc', SimGen::Decoder::TranslationUnit.generate_decoder(ir_hash))
File.write('isa.hh', SimGen::ISA::Header.generate_isa_header(ir_hash))
File.write('hart.hh', SimGen::Hart::Header.generate_hart(ir_hash))
File.write('hart.cc', SimGen::Hart::TranslationUnit.generate_hart(ir_hash))
File.write('base_ops.h', SimGen.generate_base_ops)
