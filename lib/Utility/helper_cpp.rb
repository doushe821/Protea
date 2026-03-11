require 'Utility/type'

# frozen_string_literal: true
# Utility methods simulator's code generation
module Utility
  # Utility methods simulator's code generation in C++
  module HelperCpp
    module_function

    def gen_type(type)
      actual_type = Utility.get_type(type)

      cpp_bitsize = actual_type.bitsize % 32 == 0 ? actual_type.bitsize : (actual_type.bitsize / 32 + 1) * 32
      # NOTE: while initializing m_pc, its :size is given as an argument
      # get_type is actually fine with that and considers it an int, however:
      # 1. It should be 64 bit (at least after adding any of RV64 extension)
      # 2. I feel like this can cause some issues later.
      # So that's why instead of tracking errors inside the case,
      # we assume every 'unknown' type to be unsigned, even if it's some random
      # value like '3'(integer) in case of pc initialization in cpu_state.rb
      # I am not sure if this is intentional or just haven't been fixed yet,
      # so I will only leave this comment for now.
      case actual_type.typeof
      when :s then "int#{cpp_bitsize}_t"
      when :f then "float#{cpp_bitsize}_t"
      else "uint#{cpp_bitsize}_t"
      end
    end

    def gen_small_type(type)
      actual_type = Utility.get_type(type)
      cpp_bitsize = actual_type.bitsize % 8 == 0 ? actual_type.bitsize : (actual_type.bitsize / 8 + 1) * 8

      case actual_type.typeof
      when :s then "int#{cpp_bitsize}_t"
      when :f then "float#{cpp_bitsize}_t"
      else "uint#{cpp_bitsize}_t"
      end
    end
  end
end
