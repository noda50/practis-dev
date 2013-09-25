#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'rubygems'
require 'json'
require 'rexml/document'

require 'practis'
require 'practis/database'

module Practis
  module Database


    #=== Parser for the database schema file of practis.
    class DatabaseParser

      include Database
      include Practis

      # A file path of a configuration file.
      attr_reader :file
      # Store parsed paramDefs.
      attr_reader :database_set

      # The path to ParamDefs(?) tag in a inputted parameter configuration file.
      DATABASE_PATH = "practis/databases/database"

      # Generic attributes in a database tag.
      GENERIC_ATTRS = [NAME_ATTR]

      # Condition type: add or remove a condition for a vairable.
      # These condtions are overwritten in turn.
      TABLE_TAG = "tables/table"

      FIELD_TAG = "field"
      FIELD_FIXED_TYPES = %w(float double date datetime timestamp time year)
      FIELD_VARIABLE_TYPES =
        %w(int char varchar binary varbinary blob text longtext enum set)
      CONSTRAINT_TAG = "constraint"
      OPTION_TAG = "options"

      def initialize(file)
        @file = file
        @database_set = nil
        unless filecheck
          error("input file does not exist.")
          exit
        end
      end

      #=== Parse a database schema file based on XML.
      #returned_value :: On success, it returns zero. On error, it returns -1.
      def parse
        return -1 unless filecheck
        doc = REXML::Document.new(open(file))
        database_array = []
        doc.elements.each(DATABASE_PATH) do |e|
          database = {:database => e.attributes[NAME_ATTR]}
          parse_table(e, table_array = [])
          database[:tables] = table_array
          database_array.push(database)
        end
        @database_set = JSON.generate(database_array)
        return 0
      end

      #=== add a filed matching with database and table.
      #database :: database name.
      #table :: table name.
      #arg_hash :: has to contain FIELD_ATTRS at least field, type and null.
      #returned_value :: On success, it returns zero. On error, it returns -1.
      def add_field(database, table, arg_hash)
        array = JSON.parse(@database_set, :symbolize_names => true)
        array.each do |a|
          if a[:database] == database
            a[:tables].each do |t|
              if t[:name] == table
                field_hash = {}
                FIELD_ATTRS.each { |fa|
                  field_hash[fa.to_sym] = arg_hash[fa.to_sym].nil? ? "" :
                    arg_hash[fa.to_sym] }
                FIELD_ATTRS[0..2].each do |fa|
                  if field_hash[fa.to_sym] == ""
                    warn("filed #{fa} requires any values.")
                    return -1
                  end
                end
                t[:fields].push(field_hash)
                break
              end
            end
          end
        end
        @database_set = JSON.generate(array)
        return 0
      end

      private
      # Check file exist or not.
      def filecheck
        file.nil? ? false : File.exist?(file)
      end

      def parse_field(e, l)
        e.elements.each(FIELD_TAG) do |cond|
          field_hash = {}
          FIELD_ATTRS.each { |attr|
            field_hash[attr.to_sym] = cond.attributes[attr] }
          unless FIELD_FIXED_TYPES.include?(field_hash[:type])
            match = false
            FIELD_VARIABLE_TYPES.each { |t|
              match |= field_hash[:type].include?(t) }
            unless match
              error("invalid field type. #{field_hash[:type]}")
              next
            end
          end
          unless %w(YES NO).include?(field_hash[:null])
            error("invalid null attribute. #{field_hash[:null]}")
            next
          end
          unless FIELD_KEYS.include?(field_hash[:key])
            error("invalid key attribute. #{field_hash[:key]}")
            next
          end
          l.push(field_hash)
        end
      end

      def parse_constraint(e, l)
        e.elements.each(CONSTRAINT_TAG) do |cond|
          foreign_key = cond.attributes["foreign_key"]
          references = cond.attributes["references"]
          /(?<table_name>\w+)\((?<field_name>\w+)\)/ =~ references
          l.push({:foreign_key => foreign_key,
                  :reference_table => table_name,
                  :reference_field => field_name})
        end
      end

      def parse_option(e, l)
        e.elements.each(OPTION_TAG) do |cond|
          l[:engine] = cond.attributes["engine"]
          l[:charset] = cond.attributes["charset"]
        end
      end

      def parse_table(e, l)
        e.elements.each(TABLE_TAG) do |cond|
          table_hash = {:name => cond.attributes[NAME_ATTR]}
          parse_field(cond, field_array = [])
          parse_constraint(cond, constraint_array = [])
          table_hash[:fields] = field_array
          table_hash[:constraints] = constraint_array
          parse_option(cond, table_hash)
          l.push(table_hash)
        end
      end
    end
  end
end
