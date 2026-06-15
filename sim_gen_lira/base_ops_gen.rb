require 'stringio'
require_relative 'cpp_ops'

module SimGen
  def self.generate_base_ops
    out = StringIO.new
    generate_file(out)
    out.string
  end

  class << self
    private

    HEADER = <<~'CPP'.freeze
#ifndef LIRA_STD_OPS_H
#define LIRA_STD_OPS_H

#include <stdint.h>

#ifdef __SIZEOF_INT128__
typedef unsigned __int128 uint128_t;
typedef __int128 int128_t;
#else
#error "128-bit integers not supported"
#endif
CPP

    FOOTER = "\n#endif\n"

    OP_CLASSES = [
      Lira::Not,
      Lira::Neg,
      Lira::Popcnt,
      Lira::Clz,
      Lira::Ctz,
      Lira::Reverse,
      Lira::Add,
      Lira::Sub,
      Lira::Mul,
      Lira::And,
      Lira::Orr,
      Lira::Xor,
      Lira::Lsl,
      Lira::Lsr,
      Lira::Asr,
      Lira::Eq,
      Lira::Ne,
      Lira::Slt,
      Lira::Sle,
      Lira::Sgt,
      Lira::Sge,
      Lira::Ult,
      Lira::Ule,
      Lira::Ugt,
      Lira::Uge,
      Lira::DivU,
      Lira::DivS,
      Lira::RemU,
      Lira::RemS,
      Lira::Select,
      Lira::ExtendSign,
      Lira::ExtendZero,
      Lira::ExtractLow,
    ].freeze

    def generate_file(out)
      out.puts HEADER

      OP_CLASSES.each do |op_class|
        op_class.instances_to_generate.each do |args|
          instance = op_class.new(*args)
          out.puts instance.to_cpp
        end
        out.puts
      end

      generate_special_extensions(out)

      out.puts FOOTER
    end

    def generate_special_extensions(out)
      out.puts Lira::ExtractLow.new(64, 32).to_cpp
      out.puts Lira::ExtendSign.new(32, 64).to_cpp
      out.puts Lira::ExtendZero.new(32, 64).to_cpp

      out.puts "static inline uint8_t extract_low_32_to_1(uint32_t a) { return a & 1; }"
      out.puts "static inline uint32_t extend_sign_1_to_32(uint8_t a) {"
      out.puts "  return (uint32_t)(int32_t)(int8_t)a;"
      out.puts "}"
      out.puts "static inline uint32_t extend_zero_1_to_32(uint8_t a) { return a; }"
    end
  end
end

if __FILE__ == $0
  output_file = ARGV[0] || "std_ops.h"
  File.write(output_file, SimGen.generate_base_ops)
  puts "Generated #{output_file}"
end
