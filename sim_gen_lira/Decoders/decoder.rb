# Decoders/decoder.rb
require_relative '../cpp_gen'

module SimGen
  module Decoder
    module Header
      module_function

      def generate_decoder(ir_hash)
        <<~CPP
          #ifndef GENERATED_#{ir_hash[:isa_name].upcase}_DECODER_HH_INCLUDED
          #define GENERATED_#{ir_hash[:isa_name].upcase}_DECODER_HH_INCLUDED

          #include "isa.hh"
          #include <optional>

          using namespace prot::isa;

          namespace prot::decoder {
            std::optional<Instruction> decode(const uint32_t raw_insn);
          }

          #endif
        CPP
      end
    end

    module TranslationUnit
      module_function

      def generate_decoder(ir_hash)
        instructions = ir_hash[:instructions]
        snippets = ir_hash[:snippets].to_h { |s| [s[:name], s[:seq]] }

        body = []
        instructions.each do |insn|
          decode_snippets = insn[:encoding][:decode_snippets]
          constraint_name = insn[:encoding][:constraint_decode]

          next unless constraint_name
          constraint_seq = snippets[constraint_name]
          next unless constraint_seq

          constraint_t = LiraCppGen::Translator.new(constraint_seq, :decode, 2)
          constraint_code = constraint_t.translate

          if decode_snippets.nil? || decode_snippets.empty?
            body << <<~CPP
              {
                #{constraint_code}
                if (insn.operand0) {
                  insn.m_opc = Opcode::k#{insn[:name].to_s.upcase};
                  return insn;
                }
              }
            CPP
          else
            snippet_name = decode_snippets.first
            seq = snippets[snippet_name]
            next unless seq

            translator = LiraCppGen::Translator.new(seq, :decode, 2)
            snippet_code = translator.translate

            body << <<~CPP
              {
                #{constraint_code}
                if (insn.operand0) {
                  #{snippet_code}
                  insn.m_opc = Opcode::k#{insn[:name].to_s.upcase};
                  return insn;
                }
              }
            CPP
          end
        end

        decoder_impl = body.join("\n")
        <<~CPP
          #include "decoder.hh"
          #include "base_ops.h"
          #include <optional>

          namespace prot::decoder {
          std::optional<Instruction> decode(isa::Word raw_insn) {
            Instruction insn{};
            #{decoder_impl}
            return std::nullopt;
          }
          }
        CPP
      end
    end
  end
end
