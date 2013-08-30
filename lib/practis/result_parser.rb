#!/usr/bin/ruby
# -*- coding: utf-8 -*-

require 'bigdecimal'
require 'rexml/document'

require 'practis'
require 'practis/parameter'


module Practis
  module Parser

    # Parse a parameter configuration file of PRACTIS, generate an exhaustive 
    # variables. 
    # The format of the configuration file can be checked in the 
    # "sample" directory.
    class ResultParser

      include Practis

      attr_reader :file         # A file path of a configuration file.
      attr_reader :result_set   # Store parsed variables.

      # The path to Variable tag in a inputted parameter configuration file.
      RESULT_PATH = 'practis/results/result'
      NULL_ATTR = "null"
      # Generic attributes in a result tag.
      GENERIC_ATTRS = [NAME_ATTR, DATA_TYPE_ATTR, NULL_ATTR]

      def initialize(file)
        @file = file
        unless filecheck
          error("input file does not exist.")
          exit
        end
        @result_set = nil
      end

      # Parse file configuration file. It returns a boolean value whether it 
      # suceeds or not.
      def parse
        return false unless filecheck
        doc = REXML::Document.new(open(file))
        @result_set = []
        doc.elements.each(RESULT_PATH) do |e|
          result_array = []   # [0]: name, [1]: data type, [2]:null
          get_generic(e, result_array)
          @result_set.push(result_array)
        end
        return true
      end

      private
      # Check file exist or not.
      def filecheck
        return file.nil? ? false : File.exist?(file)
      end

      # Get values of generic variable.
      def get_generic(e, l)
        GENERIC_ATTRS.each { |a| l.push(e.attributes[a]) }
      end
    end
  end
end
