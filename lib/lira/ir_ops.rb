# lira/ir_ops.rb
require_relative 'arch'

module Lira
  class TypeCheckError < StandardError; end

  module StdOperation
    def base_name
      self.class.name.split('::').last.downcase
    end

    def type_name(width, signed = false)
      sizes = [1, 8, 16, 32, 64, 128]
      prefix = signed ? "" : "u"
      rounded = sizes.find { |s| s >= width } || 128
      case rounded
      when 1   then "bool"
      when 8   then "#{prefix}int8_t"
      when 16  then "#{prefix}int16_t"
      when 32  then "#{prefix}int32_t"
      when 64  then "#{prefix}int64_t"
      when 128 then "#{prefix}int128_t"
      else "#{prefix}int#{rounded}_t"
      end
    end

    def generate_name
      if outputs.size == 1
        "#{base_name}_#{outputs.first}"
      else
        "#{base_name}_#{outputs.join('_')}"
      end
    end

    def cpp_func_name
      generate_name
    end

    def cpp_return_type
      type_name(outputs[0])
    end

    def cpp_params
      inputs.map.with_index { |w, i| "#{type_name(w)} #{('a'.ord + i).chr}" }.join(", ")
    end

    def cpp_body
      case semantic_base
      when 'not' then 'return ~a;'
      when 'neg' then 'return -a;'
      when 'add' then 'return a + b;'
      when 'sub' then 'return a - b;'
      when 'mul' then 'return a * b;'
      when 'and' then 'return a & b;'
      when 'orr' then 'return a | b;'
      when 'xor' then 'return a ^ b;'
      when 'eq'  then 'return (a == b) ? 1 : 0;'
      when 'ne'  then 'return (a != b) ? 1 : 0;'
      when 'slt' then "return ((#{type_name(inputs[0], true)})a < (#{type_name(inputs[0], true)})b) ? 1 : 0;"
      when 'sle' then "return ((#{type_name(inputs[0], true)})a <= (#{type_name(inputs[0], true)})b) ? 1 : 0;"
      when 'sgt' then "return ((#{type_name(inputs[0], true)})a > (#{type_name(inputs[0], true)})b) ? 1 : 0;"
      when 'sge' then "return ((#{type_name(inputs[0], true)})a >= (#{type_name(inputs[0], true)})b) ? 1 : 0;"
      when 'ult' then "return (a < b) ? 1 : 0;"
      when 'ule' then "return (a <= b) ? 1 : 0;"
      when 'ugt' then "return (a > b) ? 1 : 0;"
      when 'uge' then "return (a >= b) ? 1 : 0;"
      when 'lsl' then "b &= #{inputs[0] - 1}; return a << b;"
      when 'lsr' then "b &= #{inputs[0] - 1}; return a >> b;"
      when 'asr' then "b &= #{inputs[0] - 1}; return (#{type_name(inputs[0])})((#{type_name(inputs[0], true)})a >> b);"
      when 'div_u' then 'return (b == 0) ? c : a / b;'
      when 'div_s' then "return (b == 0) ? c : (#{type_name(inputs[0])})((#{type_name(inputs[0], true)})a / (#{type_name(inputs[0], true)})b);"
      when 'select' then 'return cond ? a : b;'
      when 'rem_u' then
        <<~CPP
        if (b == 0) return a;
        return a % b;
        CPP
      when 'rem_s' then
        <<~CPP
        if (b == 0) return a;
        #{type_name(inputs[0], true)} res = (#{type_name(inputs[0], true)})a % (#{type_name(inputs[0], true)})b;
        return (#{type_name(inputs[0])})res;
        CPP
      else
        raise "No cpp_body defined for operation #{semantic_base}"
      end
    end

    def to_cpp
      body_indented = cpp_body.lines.map { |l| "  #{l.chomp}" }.join("\n")
      <<~CPP
      static inline #{cpp_return_type} #{cpp_func_name}(#{cpp_params}) {
      #{body_indented}
      }
      CPP
    end

    def self.standard_sizes
      [8, 16, 32, 64, 128]
    end
  end


  class UnaryOp < Operation
    include StdOperation

    def initialize(out_bits, name: nil, semantic_base: nil)
      name ||= "#{base_name}_#{out_bits}"
      semantic_base ||= base_name
      super(name, [], [out_bits], [out_bits],
            semantic_base: semantic_base, semantic_func: nil, semantic_table: nil)
      check_signature
    end

    def check_signature
      raise TypeCheckError, "input width must be positive" unless inputs[0] > 0
      raise TypeCheckError, "output width must be positive" unless outputs[0] > 0
      raise TypeCheckError, "input != output" unless inputs[0] == outputs[0]
    end
  end

  class BinaryOp < Operation
    include StdOperation

    def initialize(bits, name: nil, semantic_base: nil)
      name ||= "#{base_name}_#{bits}"
      semantic_base ||= base_name
      super(name, [], [bits, bits], [bits],
            semantic_base: semantic_base, semantic_func: nil, semantic_table: nil)
      check_signature
    end

    def check_signature
      raise TypeCheckError, "input[0] must be positive" unless inputs[0] > 0
      raise TypeCheckError, "input[1] must be positive" unless inputs[1] > 0
      raise TypeCheckError, "output must be positive" unless outputs[0] > 0
      unless inputs[0] == inputs[1] && inputs[0] == outputs[0]
        raise TypeCheckError, "mismatched widths: #{inputs} -> #{outputs[0]}"
      end
    end
  end

  class CmpOp < Operation
    include StdOperation

    def initialize(bits, out_bits = 1, name: nil, semantic_base: nil)
      name ||= "#{base_name}_#{bits}"
      semantic_base ||= base_name
      super(name, [], [bits, bits], [out_bits],
            semantic_base: semantic_base, semantic_func: nil, semantic_table: nil)
      check_signature
    end

    def generate_name
      "#{base_name}_#{inputs[0]}"
    end

    def cpp_return_type
      type_name(1)
    end

    def check_signature
      raise TypeCheckError, "input[0] must be positive" unless inputs[0] > 0
      raise TypeCheckError, "input[1] must be positive" unless inputs[1] > 0
      raise TypeCheckError, "output must be positive" unless outputs[0] > 0
      raise TypeCheckError, "input widths differ" unless inputs[0] == inputs[1]
    end
  end

  class TernaryOp < Operation
    include StdOperation

    def initialize(bits, name: nil, semantic_base: nil)
      name ||= "#{base_name}_#{bits}"
      semantic_base ||= base_name
      super(name, [], [bits, bits, bits], [bits],
            semantic_base: semantic_base, semantic_func: nil, semantic_table: nil)
      check_signature
    end

    def check_signature
      raise TypeCheckError, "input[0] must be positive" unless inputs[0] > 0
      raise TypeCheckError, "input[1] must be positive" unless inputs[1] > 0
      raise TypeCheckError, "input[2] must be positive" unless inputs[2] > 0
      raise TypeCheckError, "output must be positive" unless outputs[0] > 0
      unless inputs[0] == inputs[1] && inputs[0] == inputs[2] && inputs[0] == outputs[0]
        raise TypeCheckError, "mismatched widths: #{inputs} -> #{outputs[0]}"
      end
    end
  end

  class ExtendOp < Operation
    include StdOperation

    def initialize(in_bits, out_bits, kind, name: nil)
      name ||= "#{kind}_#{in_bits}_to_#{out_bits}"
      super(name, [], [in_bits], [out_bits],
            semantic_base: kind, semantic_func: nil, semantic_table: nil)
      check_signature
    end

    def check_signature
      raise TypeCheckError, "input width must be positive" unless inputs[0] > 0
      raise TypeCheckError, "output width must be positive" unless outputs[0] > 0
      raise TypeCheckError, "input >= output" unless inputs[0] < outputs[0]
    end

    def generate_name
      "#{semantic_base}_#{inputs[0]}_to_#{outputs[0]}"
    end

    def cpp_return_type
      type_name(outputs[0])
    end

    def cpp_params
      "#{type_name(outputs[0])} a"
    end
  end

  class ExtractLowOp < Operation
    include StdOperation

    def initialize(in_bits, out_bits, name: nil)
      name ||= "extract_low_#{in_bits}_to_#{out_bits}"
      super(name, [], [in_bits], [out_bits],
            semantic_base: 'extract_low', semantic_func: nil, semantic_table: nil)
      check_signature
    end

    def check_signature
      raise TypeCheckError, "input width must be positive" unless inputs[0] > 0
      raise TypeCheckError, "output width must be positive" unless outputs[0] > 0
      raise TypeCheckError, "output > input" unless outputs[0] <= inputs[0]
    end

    def generate_name
      "extract_low_#{inputs[0]}_to_#{outputs[0]}"
    end

    def cpp_return_type
      type_name(outputs[0])
    end

    def cpp_params
      "#{type_name(outputs[0])} a"
    end
  end

  class Not < UnaryOp; def initialize(bits); super(bits, semantic_base: 'not'); end; end
  class Neg < UnaryOp; def initialize(bits); super(bits, semantic_base: 'neg'); end; end
  class Add < BinaryOp; def initialize(bits); super(bits, semantic_base: 'add'); end; end
  class Sub < BinaryOp; def initialize(bits); super(bits, semantic_base: 'sub'); end; end
  class Mul < BinaryOp; def initialize(bits); super(bits, semantic_base: 'mul'); end; end
  class And < BinaryOp; def initialize(bits); super(bits, semantic_base: 'and'); end; end
  class Orr < BinaryOp; def initialize(bits); super(bits, semantic_base: 'orr'); end; end
  class Xor < BinaryOp; def initialize(bits); super(bits, semantic_base: 'xor'); end; end
  class Lsl < BinaryOp; def initialize(bits); super(bits, semantic_base: 'lsl'); end; end
  class Lsr < BinaryOp; def initialize(bits); super(bits, semantic_base: 'lsr'); end; end
  class Asr < BinaryOp; def initialize(bits); super(bits, semantic_base: 'asr'); end; end
  class Eq < CmpOp; def initialize(bits); super(bits, semantic_base: 'eq'); end; end
  class Ne < CmpOp; def initialize(bits); super(bits, semantic_base: 'ne'); end; end
  class Slt < CmpOp; def initialize(bits); super(bits, semantic_base: 'slt'); end; end
  class Sle < CmpOp; def initialize(bits); super(bits, semantic_base: 'sle'); end; end
  class Sgt < CmpOp; def initialize(bits); super(bits, semantic_base: 'sgt'); end; end
  class Sge < CmpOp; def initialize(bits); super(bits, semantic_base: 'sge'); end; end
  class Ult < CmpOp; def initialize(bits); super(bits, semantic_base: 'ult'); end; end
  class Ule < CmpOp; def initialize(bits); super(bits, semantic_base: 'ule'); end; end
  class Ugt < CmpOp; def initialize(bits); super(bits, semantic_base: 'ugt'); end; end
  class Uge < CmpOp; def initialize(bits); super(bits, semantic_base: 'uge'); end; end

  class ExtendSign < ExtendOp
    def initialize(in_bits, out_bits); super(in_bits, out_bits, 'extend_sign'); end
    def cpp_body
      <<~СPP
      #{type_name(outputs[0])} val = a & ((1U << #{inputs[0]}) - 1);
      #{type_name(outputs[0])} sign = (val >> (#{inputs[0]} - 1)) & 1;
      if (sign)
        return val | (~((1U << #{inputs[0]}) - 1));
      else
        return val;
      СPP
    end
  end

  class ExtendZero < ExtendOp
    def initialize(in_bits, out_bits); super(in_bits, out_bits, 'extend_zero'); end
    def cpp_body
      "return a & ((1U << #{inputs[0]}) - 1);"
    end
  end

  class ExtractLow < ExtractLowOp
    def initialize(in_bits, out_bits); super(in_bits, out_bits); end
    def cpp_body
      "return a & ((1U << #{outputs[0]}) - 1);"
    end
  end

  class Popcnt < UnaryOp
    def initialize(bits); super(bits, semantic_base: 'popcnt'); end
    def cpp_body
      case inputs[0]
      when 8
        <<~СPP
        unsigned cnt = 0;
        while (a) { cnt += a & 1; a >>= 1; }
        return cnt;
        СPP
      when 16
        "return popcnt_8(a & 0xFF) + popcnt_8((a >> 8) & 0xFF);"
      when 32
        "return popcnt_16(a & 0xFFFF) + popcnt_16((a >> 16) & 0xFFFF);"
      when 64
        "return popcnt_32(a & 0xFFFFFFFF) + popcnt_32((a >> 32) & 0xFFFFFFFF);"
      when 128
        "return popcnt_64((uint64_t)a) + popcnt_64((uint64_t)(a >> 64));"
      else
        raise "Unsupported popcnt size"
      end
    end
  end

  class Ctz < UnaryOp
    def initialize(bits); super(bits, semantic_base: 'ctz'); end
    def cpp_body
      bits = inputs[0]
      if bits == 128
        <<~СPP
        if (a == 0) return 128;
        uint64_t lo = (uint64_t)a;
        if (lo) return ctz_64(lo);
        else return 64 + ctz_64((uint64_t)(a >> 64));
        СPP
      else
        <<~СPP
        if (a == 0) return #{bits};
        unsigned n = 0;
        while ((a & 1) == 0) { a >>= 1; n++; }
        return n;
        СPP
      end
    end
  end

  class Clz < UnaryOp
    def initialize(bits); super(bits, semantic_base: 'clz'); end
    def cpp_body
      bits = inputs[0]
      if bits == 128
        <<~СPP
        if (a == 0) return 128;
        uint64_t hi = (uint64_t)(a >> 64);
        if (hi) return clz_64(hi);
        else return 64 + clz_64((uint64_t)a);
        СPP
      else
        mask = case bits
               when 8  then "0x80"
               when 16 then "0x8000"
               when 32 then "0x80000000"
               when 64 then "0x8000000000000000ULL"
               end
        <<~СPP
        if (a == 0) return #{bits};
        unsigned n = 0;
        while ((a & #{mask}) == 0) { a <<= 1; n++; }
        return n;
        СPP
      end
    end
  end

  class Reverse < UnaryOp
    def initialize(bits); super(bits, semantic_base: 'reverse'); end
    def cpp_body
      case inputs[0]
      when 8
        <<~СPP
        a = ((a & 0xF0) >> 4) | ((a & 0x0F) << 4);
        a = ((a & 0xCC) >> 2) | ((a & 0x33) << 2);
        a = ((a & 0xAA) >> 1) | ((a & 0x55) << 1);
        return a;
        СPP
      when 16
        <<~СPP
        a = ((a & 0xFF00) >> 8) | ((a & 0x00FF) << 8);
        a = ((a & 0xF0F0) >> 4) | ((a & 0x0F0F) << 4);
        a = ((a & 0xCCCC) >> 2) | ((a & 0x3333) << 2);
        a = ((a & 0xAAAA) >> 1) | ((a & 0x5555) << 1);
        return a;
        СPP
      when 32
        <<~СPP
        a = ((a & 0xFFFF0000) >> 16) | ((a & 0x0000FFFF) << 16);
        a = ((a & 0xFF00FF00) >> 8) | ((a & 0x00FF00FF) << 8);
        a = ((a & 0xF0F0F0F0) >> 4) | ((a & 0x0F0F0F0F) << 4);
        a = ((a & 0xCCCCCCCC) >> 2) | ((a & 0x33333333) << 2);
        a = ((a & 0xAAAAAAAA) >> 1) | ((a & 0x55555555) << 1);
        return a;
        СPP
      when 64
        <<~СPP
        a = ((a & 0xFFFFFFFF00000000ULL) >> 32) | ((a & 0x00000000FFFFFFFFULL) << 32);
        a = ((a & 0xFFFF0000FFFF0000ULL) >> 16) | ((a & 0x0000FFFF0000FFFFULL) << 16);
        a = ((a & 0xFF00FF00FF00FF00ULL) >> 8) | ((a & 0x00FF00FF00FF00FFULL) << 8);
        a = ((a & 0xF0F0F0F0F0F0F0F0ULL) >> 4) | ((a & 0x0F0F0F0F0F0F0F0FULL) << 4);
        a = ((a & 0xCCCCCCCCCCCCCCCCULL) >> 2) | ((a & 0x3333333333333333ULL) << 2);
        a = ((a & 0xAAAAAAAAAAAAAAAAULL) >> 1) | ((a & 0x5555555555555555ULL) << 1);
        return a;
        СPP
      when 128
        <<~СPP
        uint64_t lo = (uint64_t)a;
        uint64_t hi = (uint64_t)(a >> 64);
        return ((uint128_t)reverse_64(lo) << 64) | reverse_64(hi);
        СPP
      end
    end
  end

  class RemU < BinaryOp
    def initialize(bits); super(bits, semantic_base: 'rem_u'); end
    def base_name; 'rem_u'; end
  end

  class RemS < BinaryOp
    def initialize(bits); super(bits, semantic_base: 'rem_s'); end
    def base_name; 'rem_s'; end
  end

  class Ror < BinaryOp
    def initialize(bits); super(bits, semantic_base: 'ror'); end
  end

  class Rol < BinaryOp
    def initialize(bits); super(bits, semantic_base: 'rol'); end
  end

  class AddOverflow < CmpOp
    def initialize(bits); super(bits, out_bits: 1, semantic_base: 'add_overflow'); end
  end

  class SubOverflow < CmpOp
    def initialize(bits); super(bits, out_bits: 1, semantic_base: 'sub_overflow'); end
  end

  class DivU < TernaryOp
    def initialize(bits); super(bits, semantic_base: 'div_u'); end
    def base_name; 'div_u'; end
  end

  class DivS < TernaryOp
    def initialize(bits); super(bits, semantic_base: 'div_s'); end
    def base_name; 'div_s'; end
  end

  class Select < Operation
    include StdOperation
    def initialize(bits)
      name = "select_#{bits}"
      super(name, [], [1, bits, bits], [bits],
            semantic_base: 'select', semantic_func: nil, semantic_table: nil)
      check_signature
    end

    def check_signature
      raise TypeCheckError, "true/false branches mismatch" unless inputs[1] == inputs[2] && inputs[1] == outputs[0]
    end

    def cpp_params
      "uint8_t cond, #{type_name(inputs[1])} a, #{type_name(inputs[1])} b"
    end
  end
end

module Lira
  class Not; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Neg; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Popcnt; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Clz; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Ctz; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Reverse; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Add; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Sub; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Mul; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class And; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Orr; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Xor; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Lsl; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Lsr; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Asr; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Eq; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Ne; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Slt; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Sle; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Sgt; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Sge; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Ult; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Ule; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Ugt; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Uge; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class DivU; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class DivS; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end
  class Select; def self.instances_to_generate; StdOperation.standard_sizes.map { |b| [b] }; end; end

  class ExtendSign
    def self.instances_to_generate
      inside = [
        [1, 13], [6, 13], [4, 13],
        [1, 21], [8, 21], [10, 21],
        [7, 12], [5, 12]
      ]
      to32 = (2..31).map { |n| [n, 32] }
      inside + to32
    end
  end

  class ExtendZero
    def self.instances_to_generate
      ExtendSign.instances_to_generate
    end
  end

  class ExtractLow
    def self.instances_to_generate
      (2..31).map { |n| [32, n] }
    end
  end

  class RemU; def self.instances_to_generate; [[32], [64]]; end; end
  class RemS; def self.instances_to_generate; [[32], [64]]; end; end
end
