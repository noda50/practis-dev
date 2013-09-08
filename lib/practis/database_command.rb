#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'rubygems'
require 'json'

require 'practis'
require 'practis/database'


module Practis
  module Database

    #=== Generate database command.
    class DatabaseCommandGenerator

      include Practis

      DATABASE_COMMAND_TYPES = %w(cdatabase ctable cgrant cgrantl cinsert
                                  dcolumn ddatabase dtable
                                  rcolumn rcount rdatabase rinnerjoin rnow
                                  rmax
                                  rtable runixtime ucolumn uglobal)

      def initialize(database_schema)
        @database_schema = JSON.parse(database_schema, :symbolize_names => true)
      end

      def get_schema
        JSON.generate(@database_schema)
      end

      def get_command(database, table, arg_hash, condition = nil)
        if arg_hash.nil?
          error("no argument hash")
          return nil
        end
        unless arg_hash.has_key?(:type)
          error("type field is required!")
          return nil
        end
        unless DATABASE_COMMAND_TYPES.include?(arg_hash[:type])
          error("invalid type field: #{arg_hash[:type]}")
          return nil
        end
        generate(database, table, arg_hash, condition)
      end
    end

    class MysqlCommandGenerator < DatabaseCommandGenerator

      def generate(database, table, arg_hash, condition)
        tbl = nil
        if !database.nil? && !table.nil?
          db = @database_schema.select { |i| i[:database] == database }
          tbl = db.map { |i| i[:tables].select { |j| j[:name] == table } }
          if tbl.length > 1
            error("there exists same name tables.")
            return nil
          elsif tbl.length < 1
            error("there exists no table :#{table}.")
            return nil
          end
          tbl = tbl[0][0]
        end
        query = ""
        case arg_hash[:type]
        when "cdatabase"
          query << "CREATE DATABASE #{database};"
        when "ctable"
          query << "CREATE TABLE #{database}.#{table} ("
          query << tbl[:fields].map { |f| FIELD_ATTRS.map { |i|
            "#{field_to_sql(i, f[i.to_sym])}" }.join(" ") }.join(", ")
          tbl[:constraints].each { |f|
            query << ", FOREIGN KEY (#{f[:foreign_key]}) REFERENCES " +
            "#{f[:reference_table]}(#{f[:reference_field]}) ON DELETE CASCADE" +
            " ON UPDATE CASCADE" }
          query << ") ENGINE=#{tbl[:engine]} CHARACTER SET #{tbl[:charset]};"
        when "cgrant"
          query << "GRANT ALL ON #{database}.* TO '#{arg_hash[:username]}'@'%';"
        when "cgrantl"
          query << "GRANT ALL ON #{database}.* TO '#{arg_hash[:username]}'@'" +
            "localhost';"
        when "cinsert"
          query << "INSERT INTO #{database}.#{table} ("
          query << tbl[:fields].map { |f| "#{f[:field]}" }.join(", ")
          query << ") VALUES ("
          query << tbl[:fields].map { |f| arg_hash[f[:field].to_sym].nil? ?
            "NULL" : "'#{arg_hash[f[:field].to_sym]}'" }.join(", ")
          query << ");"
        when "rcolumn"
          query << "SELECT * FROM #{database}.#{table}"
          query << (condition.nil? ? ";" :
            " #{condition_to_sql(database, table, condition)};")
        ## [2013/09/08 I.Noda] extend count command for general purpose.
        when "rcount"
          query << "SELECT"
          query << " #{arg_hash[:column]}," if arg_hash[:column]
          query << " COUNT(*) FROM #{database}.#{table}"
          if(!condition.nil?)
            query << " #{condition_to_sql(database, table, condition)}"
          end
          query << " GROUP BY #{arg_hash[:column]}" if arg_hash[:column]
          query << " ;"
        ## [2013/09/07 I.Noda] for unique parameter id
        when "rmax"
          query << "SELECT MAX(#{arg_hash[:column]}) FROM #{database}.#{table}"
          if(!condition.nil?)
            query << " #{condition_to_sql(database, table, condition)}"
          end
          query << " ;"
        when "rdatabase"
          query << "SHOW DATABASES;"
        when "rinnerjoin"
          query << "SELECT * FROM #{database}.#{table} INNER JOIN #{condition};"
        when "rnow"
          query << "SELECT DATE_FORMAT(NOW(), GET_FORMAT(DATETIME, 'ISO'));"
        when "rtable"
          query << "show tables from #{database};"
        when "rnow"
          query << "SELECT DATE_FORMAT(NOW(), GET_FORMAT(DATETIME, 'ISO'));"
        when "runixtime"
          query << "SELECT UNIX_TIMESTAMP();"
        when "ucolumn"
          query << "UPDATE #{database}.#{table} SET "
          query << tbl[:fields].inject([]) { |s, f|
            if arg_hash.has_key?(f[:field].to_sym)
              s.push("#{f[:field]} = " +
                     (arg_hash[f[:field].to_sym].nil? ? "NULL" :
                      " '#{arg_hash[f[:field].to_sym]}'"))
            else
              s
            end
          }.join(", ")
          query << condition_to_sql(database, table, condition) \
            unless condition.nil?
          query << ";"
        when "uglobal"
          query << "SET GLOBAL max_allowed_packet=16*1024*1024;"
        when "dcolumn"
          query << "DELETE FROM #{database}.#{table} " +
            "#{condition_to_sql(database, table, condition)};"
        when "ddatabase"
          query << "DROP DATABASE #{database};"
        when "dtable"
          query << "DROP TABLE #{database}.#{table};"
        end
        query = query.sub("  ", " ") while query.include?("  ")
        return query
      end

      private
      #=== Convert a field attribute to SQL field attribute name.
      def field_to_sql(field_attribute_type, field_attribute_value)
        (error("invalid field attribute. #{field_attribute_type}"); nil) \
          unless FIELD_ATTRS.include?(field_attribute_type)
        case field_attribute_type
        when "field" then return field_attribute_value
        when "type" then return field_attribute_value
        when "null"
          return "NOT NULL" if field_attribute_value == "NO"
          return ""
        when "key"
          case field_attribute_value
          when "PRI" then return "PRIMARY KEY"
          when "MUL" then return ""
          when "UNI" then return "UNIQUE"
          else return ""
          end
        when "default"
          return "DEFAULT #{field_attribute_value}" \
            if field_attribute_value.length > 0
          return ""
        when "extra" then return "#{field_attribute_value}"
        when "comment" then return "#{field_attribute_value}"
        end
        error("invalid field type #{field_attribute_type}, value: " +
              "#{field_attribute_value}")
        return nil
      end

      def condition_to_sql(database, table, condition)
        conds = []
        condition.split(/\s*(\ and\ |\ or\ )\s*/).each do |s|
          if s != "and" && s != "or"
            cond = s.gsub("'", "").split(/\s*\=\s*/)
            next if cond.length != 2
            conds.push({:key => cond[0], :value => cond[1]})
          end
        end
        retval = " WHERE "
        db = @database_schema.inject(nil) do |a, s|
          s[:tables].inject(nil) { |tbl, t|
            t[:name] == table ? t : tbl }.nil? ? a : s
        end
        if db.nil?
          error("specified database is not included. #{database}")
          return nil
        end
        tbl = db[:tables].inject(nil) { |a, s| s[:name] == table ? s : a }
        if tbl.nil?
          error("specified table is not included. #{table}")
          return nil
        end
        retval << conds.map { |cond|
          field = tbl[:fields].select { |f| f[:field] == cond[:key] }
          if field.length != 1
            error("condition #{cond[:key]} does not exist!")
            next
          end
          field[0][:type] == "float" || field[0][:type] == "double" ?
            "#{cond[:key]} = CAST('#{cond[:value]}' AS DECIMAL)" :
            "#{cond[:key]} = '#{cond[:value]}'"
        }.join(" AND ")
        return retval
      end
    end

    class MongoCommandGenerator < DatabaseCommandGenerator
      def generate(database, table, arg_hash, condition)
      end
    end
  end
end
