#!/usr/bin/ruby
# frozen_string_literal: true

require 'ADL/base'
require 'ADL/builder'
puts 'boop'
require 'Target/RISC-V/32I'
puts 'boop'
require 'Target/RISC-V/64F'
puts 'boop'
require 'yaml'

yaml_data = SimInfra.serialize
File.write('IR.yaml', yaml_data)
