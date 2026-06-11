# ExecEngines/naive_interpreter.rb
require_relative '../cpp_gen'

module SimGen
  module NaiveInterpreter
    module Header
      module_function

      def generate_naive_interpreter(ir_hash)
        <<~CPP
          #ifndef GENERATED_#{ir_hash[:isa_name].upcase}_INTERPRETER_HH_INCLUDED
          #define GENERATED_#{ir_hash[:isa_name].upcase}_INTERPRETER_HH_INCLUDED

          #include "base_exec_engine.hh"

          namespace prot::engine {
            class Interpreter : public ExecEngine {
            public:
              void execute(CPU &cpu, const Instruction &insn) override;
            };
          }

          #endif
        CPP
      end
    end

    module TranslationUnit
      module_function

      def generate_naive_interpreter(ir_hash)
        exec_functions = []
        branch_insns = []

        ir_hash[:instructions].each do |insn|
          name = insn[:name].to_s.upcase
          seq = insn[:semantic_seq]

          # Генерируем функцию даже для пустой семантики
          if seq && seq.stmts.any?
            translator = LiraCppGen::Translator.new(seq, :execute, 2)
            body = translator.translate
          else
            body = "  // no semantic"
          end

          exec_functions << <<~CPP
            void do#{name}(CPU &cpu, const Instruction &insn) {
              #{body}
            }
          CPP

          if seq && seq.stmts.any? && seq.stmts.any? { |s| s.kind == 'env' && s.specifier == 'setPC' }
            branch_insns << "case Opcode::k#{name}: return true;"
          end
        end

        is_branch = <<~CPP
          bool isBranchInstruction(const Instruction &insn) {
            switch (insn.m_opc) {
              #{branch_insns.join("\n")}
              default: return false;
            }
          }
        CPP

        handlers_init = ir_hash[:instructions].map do |insn|
          "m_handlers[toUnderlying(Opcode::k#{insn[:name].to_s.upcase})] = &do#{insn[:name].to_s.upcase};"
        end.join("\n    ")

        <<~CPP
          #include "naive_interpreter.hh"
          #include "std_ops.h"
          #include <cassert>
          #include <array>

          namespace prot::engine {
          using namespace prot::state;
          using namespace prot::isa;

          namespace {
            #{is_branch}
            #{exec_functions.join("\n\n")}

            template <typename T>
            constexpr auto toUnderlying(T val) requires std::is_enum_v<T> {
              return static_cast<std::underlying_type_t<T>>(val);
            }

            class ExecHandlersMap {
            public:
              using ExecHandler = void (*)(CPU &cpu, const Instruction &insn);
            private:
              std::array<ExecHandler, #{ir_hash[:instructions].size}> m_handlers{};
            public:
              constexpr ExecHandlersMap() {
                #{handlers_init}
              }
              ExecHandler get(Opcode opcode) const {
                auto idx = toUnderlying(opcode);
                if (idx >= m_handlers.size()) return nullptr;
                auto h = m_handlers[idx];
                return h;
              }
            };
            constexpr ExecHandlersMap kExecHandlers{};
          }

          void Interpreter::execute(CPU &cpu, const Instruction &insn) {
            auto handler = kExecHandlers.get(insn.m_opc);
            if (!handler) return;
            auto oldPC = cpu.getPC();
            handler(cpu, insn);
            if (!isBranchInstruction(insn))
              cpu.setPC(oldPC + getILen(insn.m_opc));
          }
          }
        CPP
      end
    end
  end
end
