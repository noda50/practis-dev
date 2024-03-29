#!/usr/bin/ruby
# -*- coding: utf-8 -*-

require 'bigdecimal'
require 'rexml/document'

require 'practis'
require 'practis/parameter'


module Practis
  module Parser

    # Parse a parameter configuration file of PRACTIS, generate an exhaustive 
    # values
    # The format of the configuration file can be checked in the 
    # "sample" directory.
    class ParameterParser

      include Practis

      attr_reader :file           # A file path of a configuration file.
      attr_reader :paramDefList   # Store parsed Parameter Definitions.

      # The path to ParamDef tag in a inputted parameter configuration file.
#      PARAMDEF_PATH = "practis/exhaustive/variables/variable"
      PARAMDEF_PATH = "practis/exhaustive/parameters/parameter"

      # Range of a parameter value
      RANGE_TYPE = "range_type"
      RANGE_RANGE = "range"
      RANGE_LIST = "list"
      RANGE_TYPES = [RANGE_RANGE, RANGE_LIST]

      # Generic tags in a parameter definition tag.
      GENERIC_ATTRS = [NAME_ATTR, DATA_TYPE_ATTR]

      # Condition type: add or remove a condition for a vairable.
      # These condtions are overwritten in turn.
      CONDITION_TAG = "conditions/condition"
      CONDITION_TYPE = "type"
      CONDITION_INCLUDE = "include"
      CONDITION_EXCLUDE = "exclude"
      CONDITION_TYPES = [CONDITION_INCLUDE, CONDITION_EXCLUDE]

      # If a change tag is range type, these tags are contained.
      RANGE_START = "start"
      RANGE_END = "end"
      RANGE_STEP = "step"
      RANGE_TAGS = [RANGE_START, RANGE_END, RANGE_STEP]

      # If a change tag is list type, the path to the list values in xml file.
      LIST_TAG = "list_values/list_value"

      # Indexes of an array that temporary stores values.
      NAME_NUM = 0        # parameter name
      ARGUMENT_NUM = 1    # argument type
      PARAMDEFS_NUM = 2   # parameter definition
      PATTERN_NUM = 2     # pattern

      def initialize(file)
        @file = file
        (error("input file does not exist."); exit) unless filecheck
        @paramDefList = nil
      end

      #=== Parse a practis parameter file configuration file.
      #returned_value :: On success, it returns zero. On error, it returns -1.
      def parse
        return -1 unless filecheck
        doc = REXML::Document.new(open(file))
        paramDef_array = []
        doc.elements.each(PARAMDEF_PATH) do |e|
          vallist = []  # a paramdef list, [0]:name, [1]:value type,
                        # [2]:paramValues (?)
          get_generic(e, vallist)
          if parse_condition(e, vallist) < 0
            error("fail to parse condition.")
          end
          paramDef_array.push(Practis::ParamDef.new(vallist[NAME_NUM],
                                                    vallist[ARGUMENT_NUM],
                                                    vallist[PATTERN_NUM]))
        end
        @paramDefList = paramDef_array
        return 0
      end

      # Simpley print paramDefs
      def print_paramDefs
        return @paramDefList.inject("") { |s, v| s << v.to_s }
      end

      private
      # Check file exist or not.
      def filecheck
        return false if file.nil?
        return File.exist?(file)
      end

      # Get values of generic paramDef.
      def get_generic(e, l)
        # Add a name and an argument type.
        GENERIC_ATTRS.each { |tag| l.push(e.attributes[tag]) }
      end

      # Convert a paramDef with value type.
      def convert_type(s, argument_type)
        case argument_type
        when DATA_TYPE_INTEGER then return s.to_i
        when DATA_TYPE_FLOAT then return s.to_f
        when DATA_TYPE_STRING then return s
        else return nil
        end
      end

      # Parse condition tag.
      def parse_condition(e, l)
        json_array = []
        e.elements.each(CONDITION_TAG) do |cond|
          hash = {}
          #condition_type = cond.attributes[CONDITION_TYPE]
          unless CONDITION_TYPES.include?(condition_type =
                                          cond.attributes[CONDITION_TYPE])
            error("Specified condition type is invalid. #{condition_type}")
            return -1
          end
          unless RANGE_TYPES.include?(range_type = cond.attributes[RANGE_TYPE])
            error("Specified range type is invalid.", range_type)
            return -2
          end
          case hash[:type] = "#{condition_type}_#{range_type}"
          when "include_range", "exclude_range"
            hash[:start] = convert_type(cond.elements[RANGE_START].text,
                                        l[ARGUMENT_NUM])
            hash[:end] = convert_type(cond.elements[RANGE_END].text,
                                      l[ARGUMENT_NUM])
            hash[:step] = convert_type(cond.elements[RANGE_STEP].text,
                                       l[ARGUMENT_NUM])
          when "include_list", "exclude_list"
            list_array = []
            cond.elements.each(LIST_TAG) { |list|
              val = convert_type(list.text, l[ARGUMENT_NUM])
              list_array.push(val) }
            hash[:list] = list_array
          end
          json_array.push(hash)
        end
        l.push(JSON.generate(json_array))
        return 0
      end
    end
  end
end
