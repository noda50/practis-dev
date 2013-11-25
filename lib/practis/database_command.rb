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
                                  drecord ddatabase dtable
                                  rrecord rcount rdatabase rinnerjoin rnow
                                  rmax rdiscrecord 
                                  rtable runixtime urecord uglobal)

      def initialize(database_schema)
        @database_schema = JSON.parse(database_schema, :symbolize_names => true)
        setup() ; ##[2013/09/15 I.Noda]
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

      ##--------------------------------------------------
      ##---setup()
      ##   setup hash table for lookup
      def setup()
        @databaseDef = {} ;
        @database_schema.each{|db|
          tableDef = {} ;
          @databaseDef[db[:database]] = { :schema => db, :table => tableDef } ;
          db[:tables].each{|table|
            fieldDef = {} ;
            tableDef[table[:name]] = {:schema => table, :field => fieldDef} ;
            table[:fields].each{|field|
              fieldDef[field[:field]] = field ;
            }
          }
        }
      end
      ##--------------------------------------------------
      ##---getDatabaseDef(database)
      def getDatabaseDef(database)
        dbDef = @databaseDef[database] ;
        if(dbDef.nil?) then
          error("unknown database: #{database}") ;
          raise("unknown database: #{database}") ;
        else
          return dbDef ;
        end
      end

      ##--------------------------------------------------
      ##---getDatabaseSchema(database)
      def getDatabaseSchema(database)
        getDatabaseDef(database)[:schema] ;
      end

      ##--------------------------------------------------
      ##---getDatabaseTables(database)
      def getDatabaseTables(database)
        getDatabaseDef(database)[:table] ;
      end

      ##--------------------------------------------------
      ##---getTableDef(database, table)
      def getTableDef(database, table)
        tblDef = getDatabaseTables(database)[table] ;
        if(tblDef.nil?) then
          error("unknown table: #{table} in #{database}") ;
          raise("unknown table: #{table} in #{database}") ;
        else
          return tblDef ;
        end
      end

      ##--------------------------------------------------
      ##---getTableSchema(database, table)
      def getTableSchema(database, table)
        getTableDef(database, table)[:schema] ;
      end

      ##--------------------------------------------------
      ##---getTableFields(database, table)
      def getTableFields(database, table)
        getTableDef(database, table)[:field] ;
      end

      ##--------------------------------------------------
      ##---getFieldSchema(database, table, field)
      def getFieldSchema(database, table, field)
        fldDef = getTableFields(database,table)[field] ;
        if(fldDef.nil?) then
          error("unknown field: #{field} on #{table} in #{database}") ;
          raise("unknown field: #{field} on #{table} in #{database}") ;
        else
          return fldDef ;
        end
      end

      ##--------------------------------------------------
      ##---getFieldType(database, table, field)
      def getFieldType(database, table, field)
        getFieldSchema(database, table, field)[:type] ; 
      end
    end

    class MysqlCommandGenerator < DatabaseCommandGenerator

      ##::::::::::::::::::::::::::::::::::::::::::::::::::
      Eps_RealComp = 1.0e-6;
      InnerRatio_RealComp = (1.0 - Eps_RealComp)
      OuterRatio_RealComp = (1.0 + Eps_RealComp)

      ##--------------------------------------------------
      def generate(database, table, arg_hash, condition)
        #[2013/09/15 I.Noda] 
        # now, using getTableSchema()
#        tbl = nil
#        if !database.nil? && !table.nil?
#          db = @database_schema.select { |i| i[:database] == database }
#          tbl = db.map { |i| i[:tables].select { |j| j[:name] == table } }
#          if tbl.length > 1
#            error("there exists same name tables.")
#            return nil
#          elsif tbl.length < 1
#            error("there exists no table :#{table}.")
#            return nil
#          end
#          tbl = tbl[0][0]
#        end
        tbl = ((!database.nil? && !table.nil?) ?
               getTableSchema(database, table) :
               nil) ;
        query = ""
        case arg_hash[:type]
        when "cdatabase"
          query << "CREATE DATABASE #{database};"
        when "ctable"
          query << "CREATE TABLE #{database}.#{table} ("
          indexedFields = [];
          query << tbl[:fields].map { |f| 
            FIELD_INDEXED.each{|key,value| 
              indexedFields.push(f[:field]) if(f[key.to_sym] == value)
            }
            FIELD_ATTRS.map { |i|
            "#{field_to_sql(i, f[i.to_sym])}" }.join(" ") }.join(", ")
          tbl[:constraints].each { |f|
            indexedFields.delete(f[:foreign_key]);
            query << ", FOREIGN KEY (#{f[:foreign_key]}) REFERENCES " +
            "#{f[:reference_table]}(#{f[:reference_field]}) ON DELETE CASCADE" +
            " ON UPDATE CASCADE" }
          if(indexedFields.length > 0) then
            query << ", "
            query << indexedFields.map{|f| "INDEX(#{f})"}.join(",")
          end
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
        when "rrecord"
          query << "SELECT * FROM #{database}.#{table}"
          query << (condition.nil? ? ";" :
            " #{condition_to_sql(database, table, condition)};")
        ## [2013/09/08 I.Noda] extend count command for general purpose.
        when "rcount"
          query << "SELECT"
          query << " #{arg_hash[:record]}," if arg_hash[:record]
          query << " COUNT(*) FROM #{database}.#{table}"
          if(!condition.nil?)
            query << " #{condition_to_sql(database, table, condition)}"
          end
          query << " GROUP BY #{arg_hash[:record]}" if arg_hash[:record]
          query << " ;"
        ## [2013/09/07 I.Noda] for unique parameter id
        when "rmax"
          query << "SELECT MAX(#{arg_hash[:record]}) FROM #{database}.#{table}"
          if(!condition.nil?)
            query << " #{condition_to_sql(database, table, condition)}"
          end
          query << " ;"
        ## [2013/11/25 H-Matsushima] for unique parameters
        when "rdiscrecord"
          query << "SELECT DISTINCT #{condition} FROM #{database}.#{table};"
        when "rdatabase"
          query << "SHOW DATABASES;"
        when "rinnerjoin"
          # query << "SELECT * FROM #{database}.#{table} INNER JOIN #{condition};"
          query << "SELECT * FROM #{database}.#{table} INNER JOIN #{condition[0]}"
          if(!condition[1].nil?)
            query << " #{condition_to_sql(database, table, condition[1])}"
          end
        when "rnow"
          query << "SELECT DATE_FORMAT(NOW(), GET_FORMAT(DATETIME, 'ISO'));"
        when "rtable"
          query << "show tables from #{database};"
        when "rnow"
          query << "SELECT DATE_FORMAT(NOW(), GET_FORMAT(DATETIME, 'ISO'));"
        when "runixtime"
          query << "SELECT UNIX_TIMESTAMP();"
        when "urecord"
          query << "UPDATE #{database}.#{table} SET "
          query << tbl[:fields].inject([]) { |s, f|
            if arg_hash.has_key?(f[:field].to_sym)
              s.push("#{f[:field]} = " +
                     (arg_hash[f[:field].to_sym].nil? ? "NULL" :
                      "'#{arg_hash[f[:field].to_sym]}'"))
            else
              s
            end
          }.join(", ")
          unless condition.nil?
            query << condition_to_sql(database, table, condition)
          end
          query << ";"
        when "uglobal"
          query << "SET GLOBAL max_allowed_packet=16*1024*1024;"
        when "drecord"
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
        unless FIELD_ATTRS.include?(field_attribute_type) then
          (error("invalid field attribute. #{field_attribute_type}"); nil) 
        end

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
          if field_attribute_value.length > 0 then
            return "DEFAULT #{field_attribute_value}" 
          else
            return ""
          end
        when "extra" then return "#{field_attribute_value}"
        when "comment" then return "#{field_attribute_value}"
        end
        error("invalid field type #{field_attribute_type}, value: " +
              "#{field_attribute_value}")
        return nil
      end

      ##------------------------------------------------------------
      def condition_to_sql(database, table, condition)
        if(condition.is_a?(String))
          # [Okada's original]
          condition_to_sql_byString(database, table, condition) ;
        else
          # [Noda's structured one]
          condition_to_sql_byArray(database, table, condition) ;
        end
      end

      ##------------------------------------------------------------
      def condition_to_sql_byString(database, table, condition)
        warn("!!!condition_to_sql_byString() is obsolute!!!") ;
        caller().each{|stack| warn("...called from: #{stack}")} ;

        conds = []
        condition.split(/\s*(\ and\ |\ or\ )\s*/).each do |s|
          if s != "and" && s != "or"
            cond = s.gsub("'", "").split(/\s*\=\s*/)
            next if cond.length != 2
            conds.push({:key => cond[0], :value => cond[1]})
          end
        end
        retval = " WHERE "
        # [2013/09/15 I.Noda] 
        # now, using getTableField() method to pickup field defs.
#        db = @database_schema.inject(nil) do |a, s|
#          s[:tables].inject(nil) { |tbl, t|
#            t[:name] == table ? t : tbl }.nil? ? a : s
#        end
#        if db.nil?
#          error("specified database is not included. #{database}")
#          return nil
#        end
#        tbl = db[:tables].inject(nil) { |a, s| s[:name] == table ? s : a }
#        if tbl.nil?
#          error("specified table is not included. #{table}")
#          return nil
#        end
        retval << conds.map { |cond|
#          field = tbl[:fields].select { |f| f[:field] == cond[:key] }
#          if field.length != 1
#            error("condition #{cond[:key]} does not exist!")
#            next
#          end
          field = getFieldSchema(database, table, cond[:key]) ;
          #<<<<<[2013/09/13 I.Noda]
          # for precise comparison of double value
#          field[0][:type] == "float" || field[0][:type] == "double" ?
#            "#{cond[:key]} = CAST('#{cond[:value]}' AS DECIMAL)" :
#            "#{cond[:key]} = (#{cond[:value]} * 1.0)" :
#            "#{cond[:key]} = '#{cond[:value]}'"
          condstr = nil ;
          col = cond[:key] ;
          val = cond[:value] ;
#          if(field[0][:type] == "float" || field[0][:type] == "double") then
          if(field[:type] == "float" || field[:type] == "double") then
            valA = val.to_f * OuterRatio_RealComp ;
            valB = val.to_f * InnerRatio_RealComp ;
            if(val.to_f > 0.0) then
              condstr = "`#{col}` BETWEEN #{valB} AND #{valA}" ;
            else
              condstr = "`#{col}` BETWEEN #{valA} AND #{valB}" ;
            end
          else
            condstr = "`#{col}` = '#{val}'" ;
          end
          condstr ;
          #>>>>>[2013/09/13 I.Noda]
        }.join(" AND ")
        return retval
      end

      ##------------------------------------------------------------
      ##[2013/09/14 I.Noda]
      ## (not used yet)
      ## S-exp like format for condition
      ## <Condition> ::= <Expr> | nil
      ## <Expr> ::= <Literal> | <Atom> | <Form>
      ## <Literal> ::= <<Ruby String>> || <<Ruby Numeral>>
      ## <Atom> ::= :true | :false | :null
      ## <Form> ::= <CompForm> | <LogicForm> | <ValueForm> | <DirectForm>
      ## <CompForm> ::= [<BinaryOp>, <Expr>, <Expr>]
      ##              | [<TriaryOp>, <Expr>, <Expr>, <Expr>]
      ## <BinaryOp> ::= :eq | :gt | :ge | :lt | :le
      ## <TriaryOp> ::= :between
      SqlCond_CompOp = ({ :eq => ({ :arity => 2, :form => '%s = %s', 
                                    :float => :relax }),
                          :ne => ({ :arity => 2, :form => '%s <> %s',
                                    :float => :relax }),
                          :gt => ({ :arity => 2, :form => '%s > %s' }),
                          :ge => ({ :arity => 2, :form => '%s >= %s' }),
                          :lt => ({ :arity => 2, :form => '%s < %s' }),
                          :le => ({ :arity => 2, :form => '%s <= %s' }),
                          :between => ({ :arity => 3, 
                                         :form => '%s BETWEEN %s AND %s' }),
                          }) ;
      ## <LogicForm> ::= [:and, <Expr>, ...]
      ##               | [:or, <Expr>, ...]
      ##               | [:not, <Expr>]
      SqlCond_LogicalOp = ({ :and => ({ :arity => :any, 
                                        :form => '%s AND %s',
                                        :null => 'TRUE'}),
                             :or =>  ({ :arity => :any,
                                        :form => '%s OR %s',
                                        :null => 'FALSE'}),
                             :not => ({ :arity => 1, :form => 'NOT %s'}),
                           });
      ## <ValueForm> ::= <MathOpForm> | <FunctionForm> | <FieldForm>
      ## <MathOpForm> ::= [<MathOp>, <Expr>, <Expr>]
      ## <MathOp> ::= :add | :sub | :mul | :div
      ## <FunctionForm> ::= [:function, <FuncName>, <Expr>,...]
      ## <FieldForm> ::= [:field, <FieldName> [<TableName>]]
      ## <FuncName> ::= <<Ruby String>>
      ## <FieldName> ::= <<Ruby String>>
      ## <DirectForm> ::= [:direct, <<SQL form in Ruby String>>]
      SqlCond_MathOp = ({ :add => ({ :arity => 2,
                                     :form => '%s + %s'}),
                          :sub => ({ :arity => 2,
                                     :form => '%s - %s'}),
                          :mul => ({ :arity => 2,
                                     :form => '%s * %s'}),
                          :div => ({ :arity => 2,
                                     :form => '%s / %s'}),
                        }) ;

      ##------------------------------
      def condition_to_sql_byArray(database, table, condition)
        if(condition.nil?)
          return "" ;
        else
          statement = " WHERE %s" ;
          expr = conditionToSql_Expr(database, table, condition) ;
          r = statement % expr ;
          debug("convert: #{condition} -> #{r}") ;
          return r ;
        end
      end

      ##------------------------------
      def conditionToSql_Expr(database, table, condition)
        case(condition)
        when String, Numeric, Time then
          return conditionToSql_Literal(database, table, condition) ;
        when Symbol then
          return conditionToSql_Atom(database, table, condition);
        when Array then
          return conditionToSql_Form(database, table, condition) ;
        else
          error("unknown condition for SQL: #{condition}") ;
          raise("unknown condition for SQL: #{condition}") ;
        end
      end

      ##------------------------------
      def conditionToSql_Literal(database, table, condition)
        expr = nil ;
        case(condition)
        when String then
          expr = "'#{condition}'";
          expr.instance_eval{@type=String} ;
        when Time then
          expr = "'#{condition.strftime("%Y-%m-%d %H:%M:%S")}'";
          expr.instance_eval{@type=Time}
        when Numeric then ## only Numeric value is delay-evaluated
          expr = condition ;
        else
          error("unknown literal for SQL form : #{condition}");
          raise("unknown literal for SQL form : #{condition}");
        end
        return expr ;
      end

      ##------------------------------
      def conditionToSql_Atom(database, table, condition)
        expr = nil ;
        case(condition)
        when :true then expr ='TRUE' ; expr.instance_eval{@type=:boolean} ;
        when :false then expr = 'FALSE' ; expr.instance_eval{@type=:boolean} ;
        when :null then expr = 'NULL' ; expr.instance_eval{@type=NilClass} ;
        else
          error("unknown atom value for SQL: #{condition}");
          raise("unknown atom value for SQL: #{condition}") ;
        end
        return expr ;
      end

      ##------------------------------
      def conditionToSql_Form(database, table, condition)
        op = condition[0] ;
        if(SqlCond_CompOp[op]) then
          return conditionToSql_CompForm(database, table, condition)
        elsif(SqlCond_LogicalOp[op]) then
          return conditionToSql_LogicalForm(database, table, condition)
        elsif(SqlCond_MathOp[op])
          return conditionToSql_MathForm(database, table, condition)
        elsif(op == :field)
          return conditionToSql_Field(database, table, condition)
        elsif(op == :function)
          return conditionToSql_Function(database, table, condition)
        elsif(op == :direct)
          return conditionToSql_Direct(database, table, condition)
        else
          error("unknown SQL Form : #{condition}") ;
          raise("unknown SQL Form : #{condition}") ;
        end
      end

      ##------------------------------
      def conditionToSql_CompForm(database, table, condition)
        opInfo = SqlCond_CompOp[condition[0]] ;
        return conditionToSql_OpForm(database, table, condition, opInfo);
      end

      ##------------------------------
      def conditionToSql_LogicalForm(database, table, condition)
        opInfo = SqlCond_LogicalOp[condition[0]] ;
        return conditionToSql_OpForm(database, table, condition, opInfo);
      end

      ##------------------------------
      def conditionToSql_OpForm(database, table, condition, opInfo)
        if(opInfo[:arity] == :any) then
          return conditionToSql_OpFormNAry(database, table, condition, opInfo);
        else ## opInfo[:arity] should be an integer
          return conditionToSql_OpFormFixedAry(database, table, condition, opInfo);
        end
      end

      ##------------------------------
      def conditionToSql_OpFormNAry(database, table, condition, opInfo)
        expr = nil
        if(condition.length < 2) then
          expr = opInfo[:null] ;
        else
          form = conditionToSql_Expr(database, table, condition[1]) ;
          (2...condition.length).each{|i|
            arg = conditionToSql_Expr(database, table, condition[i]) ;
            form = opInfo[:form] % [form.to_s, arg.to_s] ;
          }
          expr = "(#{form})" ;
        end
        expr.instance_eval{@type=:boolean};
        return expr ;
      end

      ##------------------------------
      def conditionToSql_OpFormFixedAry(database, table, condition, opInfo)
        expr = nil ;
        if(condition.length != opInfo[:arity]+1) then
          error("wrong arity for the SQL operator: #{condition}, #{opInfo}");
          raise("wrong arity for the SQL operator: #{condition}, #{opInfo}");
        else
          # collect converted args.
          isFloat = false ;
          fieldArgs = [] ;
          args = (1..opInfo[:arity]).map{|i|
            arg = conditionToSql_Expr(database, table, condition[i]) ;
            isFloat = true if(arg.is_a?(Float) ||
                              arg.instance_eval{@type} == Float) ;
            fieldArgs.push(i-1) if(arg.instance_eval{@isField}) ;
            arg;
          }
          # check needs to relax comparison for float
          if(isFloat && opInfo[:float] == :relax)
            ## for :eq and :ne comparison of float values
            expr = conditionToSql_OpFormRelaxedComp(database, table, condition,
                                                    opInfo, args, fieldArgs) ;
          else
            #normal form
            expr = opInfo[:form] % args ;
            expr = "(#{expr})";
          end
        end
        expr.instance_eval{@type=:boolean}
        return expr ;
      end

      ##------------------------------
      def conditionToSql_OpFormRelaxedComp(database, table, condition,
                                           opInfo, args, fieldArgs)
        newCond = nil ;
        (pivot,rest) = args ;
        if(fieldArgs.length > 0 && fieldArgs[0] > 0) then
          (rest, pivot) = args ;
        end
        if(rest.is_a?(Numeric))
          valA = rest * InnerRatio_RealComp ;
          valB = rest * OuterRatio_RealComp ;
          newCond = (rest >= 0 ?
                     [:between, [:direct, pivot], 
                      [:direct, valA], [:direct, valB]] :
                     [:between, [:direct, pivot], 
                      [:direct, valB], [:direct, valA]]) ;
        else
          newCond = [:or, 
                     [:between, [:direct, pivot],
                      [:mul, [:direct, rest], InnerRatio_RealComp],
                      [:mul, [:direct, rest], OuterRatio_RealComp]],
                     [:between, [:direct, pivot],
                      [:mul, [:direct, rest], OuterRatio_RealComp],
                      [:mul, [:direct, rest], InnerRatio_RealComp]]] ;
        end
        if(condition[0] == :ne)
          newCond = [:not, newCond] ;
        end
        return conditionToSql_Expr(database, table, newCond) ;
      end

      ##------------------------------
      def conditionToSql_Field(database, table, condition)
        fieldName = condition[1] ;
        expr = "`#{fieldName}`" ;
        typeName = getFieldType(database, table, fieldName) ;
        case(typeName)
        when "float", "double" then type = Float ;
        when "int" then type = Integer ;
        when "time", "datetime", "date" then type = Time ;
        when "boolean" then type = :boolean ;
        else type = String ;
        end
        expr.instance_eval{@type = type; @isField = true};
        return expr ;
      end

      ##------------------------------
      def conditionToSql_MathForm(database, table, condition)
        opInfo = SqlCond_MathOp[condition[0]] ;
        if((condition.length() - 1) != opInfo[:arity]) then
          error("arity does not match: #{condition}, #{opInfo}") ;
          raise("arity does not match: #{condition}, #{opInfo}") ;
        else
          isFloat = false ;
          lastType = nil ;
          args = (1...condition.length).map{|i|
            arg = conditionToSql_Expr(database, table, condition[i])
            lastType = arg.instance_eval{@type} ;
            isFloat = true if lastType == Float ;
            arg ;
          }
          expr = "(" + (opInfo[:form] % args) + ")" ;
          expr.instance_eval{@type=(isFloat ? Float : lastType)};
          return expr ;
        end
      end

      ##------------------------------
      def conditionToSql_Function(database, table, condition)
        funcName = condition[1] ;
        args = (2...condition.length).map{|i|
          arg = conditionToSql_Expr(database, table, condition[i]) ;
          arg
        }
        expr = "#{funcName}(#{args.join(",")})" ;
        return expr ;
      end

      ##------------------------------
      def conditionToSql_Direct(database, table, condition)
        return condition[1];
      end

      ##------------------------------
      ## sample of structured cond
      #[:eq, 1, 2],
      #[:gt, [:field, "sFoo"],'bar baz'],
      #[:ge, [:field, "iBaz"], 345],
      #[:lt, 3, [:field, "fBar"]],
      #[:le, [:field, "tTime"], Time.now],
      #[:ne, [:field, "fFoo"], 3.14],
      #[:eq, -2.718, [:field, "fBaz"]],
      #[:eq, [:add, 2.718, 4], [:field, "fBaz"]],
      #[:between, [:field, "iFoo"], 5, 8],
      #[:and, [:or, [:eq, 1, 2], [:gt, [:field, 'foo'], 4]], :false]


    end

    class MongoCommandGenerator < DatabaseCommandGenerator
      def generate(database, table, arg_hash, condition)
      end
    end
  end
end
