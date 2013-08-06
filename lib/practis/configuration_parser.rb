#!/usr/bin/ruby
# -*- coding: utf-8 -*-

require 'bigdecimal'
require 'json'
require 'logger'
require 'rexml/document'

module Practis
  module Parser

    #=== Parser of Practis configuration.
    class ConfigurationParser

      include Practis

      DEBUG_LEVEL = "debug_level"
      DEBUG_LEVEL_FATAL = "FATAL"
      DEBUG_LEVEL_ERROR = "ERROR"
      DEBUG_LEVEL_WARN = "WARN"
      DEBUG_LEVEL_INFO = "INFO"
      DEBUG_LEVEL_DEBUG = "DEBUG"

      DEBUG_OUTPUT = "debug_output"
      DEBUG_OUTPUT_STDOUT = "STDOUT"
      DEBUG_OUTPUT_STDERR = "STDERR"

      attr_accessor :file
      attr_accessor :configurations

      #file :: The path to the configuration file.
      def initialize(file)
        # A file path of a configuration file.
        @file = file
        unless filecheck
          STDERR.puts("input file does not exist.")
          nil
        end
        @configurations = {}
      end

      #=== Configuation file checker.
      #Check file exist or not.
      def filecheck
        @file.nil? ? false : File.exist?(@file)
      end

      def get_debug_level
        if (level = read(DEBUG_LEVEL)).nil?
          Logger::WARN
        else
          case level
          when DEBUG_LEVEL_FATAL then Logger::FATAL
          when DEBUG_LEVEL_ERROR then Logger::ERROR
          when DEBUG_LEVEL_WARN then Logger::WARN
          when DEBUG_LEVEL_INFO then Logger::INFO
          when DEBUG_LEVEL_DEBUG then Logger::DEBUG
          else Logger::WARN
          end
        end
      end

      def get_debug_output
        if (output = read(DEBUG_OUTPUT)).nil?
          STDERR
        else
          case output
          when DEBUG_OUTPUT_STDOUT then STDOUT
          when DEBUG_OUTPUT_STDERR then STDERR
          else STDERR
          end
        end
      end
    end

    #=== Parser of Practis configuration.
    class XmlConfigurationParser < ConfigurationParser

      #include Practis

      CONFIGURATION_PATH = "practis/configuration"

      # name of config tag
      CONFIG_TAG = "config"
      # name of name tag
      NAME_TAG = "name"
      # name of type tag
      TYPE_TAG = "type"
      # value tag
      VALUE_TAG = "value"
      # item tag
      ITEM_TAG = "item"

      GENERIC_ATTRIBUTES = [NAME_TAG, TYPE_TAG]

      #=== Parse method.
      #At first, call this method and parse XML elements.
      #returned_value :: On success, it returns zero. On error, it returns -1.
      def parse
        (error("configuration file does not exist: #{@file}"); return -1) \
          unless filecheck
        parse_configs(REXML::Document.new(open(@file))
                      .elements[CONFIGURATION_PATH])
        return 0
      end

      #=== Read method.
      #Return matching value with name.
      #name :: a key to find the value.
      #returned_value :: value of matching element.
      def read(name)
        if @configurations.key?(name)
          return @configurations[name]
        end
        return nil
      end

      #=== to_s method.
      #Convert configuration variable as a string.
      def to_s
        str = ""
        @configurations.each_pair {|key, value| str << "#{key}: #{value}\n" }
        str
      end

      private
      #=== Convert a variable with variable type.
      def convert_type(s, argument_type)
        case argument_type
        when ARG_INT then s.to_i
        when ARG_FLOAT then BigDecimal(s)
        when ARG_STRING then s
        else nil
        end
      end

      #=== Parse config tag elements and store the value as hash.
      #e :: config tag elements.
      def parse_configs(e)
        e.elements.each(CONFIG_TAG) do |config|
          h = parse_config(config)
          @configurations[h[NAME_TAG]] = h[VALUE_TAG] unless h.nil?
        end
      end

      #e :: config tag element.
      #returned_value :: config element as a hash.
      def parse_config(e)
        h = {}
        attr = e.attributes
        GENERIC_ATTRIBUTES.each do |tag|
          if attr.key?(tag)
            h[tag] = attr[tag]
          else
            error("generic attribute does not exist: #{tag}")
            nil
          end
        end
        if e.elements.size > 0
          items = []
          e.elements.each(ITEM_TAG) { |item| items << item.text }
          h[VALUE_TAG] = items
        else
          h[VALUE_TAG] = e.text
        end
        return h
      end
    end

    #=== Parser of JSON practis configuration.
    class JsonConfigurationParser < ConfigurationParser

      #=== Parse method.
      #At first, call this method and parse XML elements.
      #returned_value :: On success, it returns zero. On error, it returns -1.
      def parse
        (error("configuration file does not exist: #{@file}"); return -1) \
          unless filecheck
        begin
          @configurations = JSON.parse(File.open(@file, "rb").read)
        rescue Exception => e
          error("fail to parse JSON configuration file. #{e.message}")
          error(e.backtrace)
          raise e
        end
        debug(@configurations)
        return 0
      end

      #=== Read method.
      #Return matching value with name.
      #name :: a key to find the value.
      #returned_value :: value of matching element.
      def read(name)
        return rread(name, @configurations)
      end

      private
      def rread(name, obj)
        case obj.class.name
        when "Array"
          obj.each do |o|
            unless (retval = rread(name, o)).nil?
              return retval
            end
          end
        when "Hash"
          obj.each_key do |key|
            return obj[key] if key == name
            unless (retval = rread(name, obj[key])).nil?
              return retval
            end
          end
        else nil
        end
      end
    end
  end
end
