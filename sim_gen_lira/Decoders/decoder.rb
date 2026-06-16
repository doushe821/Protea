# Decoders/decoder.rb
require_relative '../cpp_gen'

module SimGen
  module Decoder
    module Header
      module_function

      def generate_decoder(arch)
        <<~CPP
          #ifndef GENERATED_#{arch.name.upcase}_DECODER_HH_INCLUDED
          #define GENERATED_#{arch.name.upcase}_DECODER_HH_INCLUDED

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

      def generate_decoder(arch)
        snippets = arch.snippets.to_h { |s| [s.name, s.seq] }

        body = []
        arch.instructions.each do |insn|
          constraint_name = insn.encoding.constraint_decode
          decode_names = insn.encoding.decode

          next unless constraint_name && decode_names
          constraint_seq = snippets[constraint_name]
          next unless constraint_seq

          operand_calls = decode_names.each_with_index.map { |name, idx|
            "insn.operand#{idx} = #{name}(raw_insn);"
          }.join("\n    ")

          body << <<~CPP
            if (#{constraint_name}(raw_insn)) {
              #{operand_calls}
              insn.m_opc = Opcode::k#{insn.name.to_s.upcase};
              return insn;
            }
          CPP
        end

        decoder_impl = body.join("\n")
        <<~CPP
          #include "decoder.hh"
          #include "snippets.h"
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
