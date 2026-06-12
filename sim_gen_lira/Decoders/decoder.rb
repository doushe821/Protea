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
          mask = insn[:encoding][:const_mask]
          const_part = insn[:encoding][:const_part]
          decode_snippets = insn[:encoding][:decode_snippets]

          if decode_snippets.nil? || decode_snippets.empty?
            # Инструкция без полей (например, fence, ecall, ebreak)
            body << <<~CPP
              if ((raw_insn & #{mask}) == #{const_part}) {
                insn.m_opc = Opcode::k#{insn[:name].to_s.upcase};
                return insn;
              }
            CPP
          else
            snippet_name = decode_snippets.first
            seq = snippets[snippet_name]
            next unless seq

            translator = LiraCppGen::Translator.new(seq, :decode, 2)
            snippet_code = translator.translate

            body << <<~CPP
              if ((raw_insn & #{mask}) == #{const_part}) {
                #{snippet_code}
                insn.m_opc = Opcode::k#{insn[:name].to_s.upcase};
                return insn;
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
