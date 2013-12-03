#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'rubygems'
require 'json'
require 'mysql2'
require 'timeout'
##<<<[2013/09/04 I.Noda]
## for exclusive connection use
require 'thread'
##>>>[2013/09/04 I.Noda]

require 'practis'
require 'practis/database'
require 'practis/database_command'
require 'practis/database_parser'


module Practis
  module Database


    #=== Database connector.
    class DatabaseConnector

      include Practis

      # a hash that stores connectors to all kinds of databases
      attr_reader :connectors
      # storing database schema
      attr_reader :database_parser

      #=== initialize method.
      #database_file :: a database configuration file
      def initialize(database_file)
        @connectors = {}
        @database_parser = Practis::Database::DatabaseParser.new(database_file)
        @database_parser.parse
      end
      
      def setup_database(paramDefs, result_set, config, doe_definitions=nil)
        # add parameter fields to parameter table
        paramDefs.each do |paramDef|
          if (type_field = type_to_sqltype(paramDef.type.to_s)).nil?
            error("type field requires any types. #{paramDef}")
            next
          end
          if @database_parser.add_field(
              config.read("#{DB_PARAMETER}_database_name"),
              config.read("#{DB_PARAMETER}_database_tablename"),
              # [2013/09/08 I.Noda] for speed up in large-scale sim.
              #{field: paramDef.name, type: type_field, null: "NO"}
              {field: paramDef.name, type: type_field, null: "NO", key: "MUL"}
                                       ) < 0
            error("fail to add a filed. #{paramDef.name}, #{type_field}")
          end
        end
        # add result fields to result table
        result_set.each do |r|
          if (type_field = type_to_sqltype(r[1])).nil?
            error("type field requires any types. #{r}")
            next
          end
          if @database_parser.add_field(
              config.read("#{DB_RESULT}_database_name"),
              config.read("#{DB_RESULT}_database_tablename"),
              {field: r[0], type: type_field, null: r[2]}
                                       ) <  0
            error("fail to add a field. #{r[0]}, #{type_field}")
          end
        end
        # <<<=== [2013/10/04 written by H-Matsushima]
        # === add f-test fields to f-test table ===
        paramDefs.each do |paramDef|
          if doe_definitions[paramDef.name]["is_assigned"]
            if (type_field = type_to_sqltype(paramDef.type.to_s)).nil?
              error("type field requires any types. #{paramDef}")
              next
            end
            # add Orthogonal Table
            if @database_parser.add_field(
                config.read("#{DB_ORTHOGONAL}_database_name"),
                config.read("#{DB_ORTHOGONAL}_database_tablename"),
                {field: "#{paramDef.name}", type: "Varchar(64)", null: "NO", key: "MUL"}
                                         ) < 0
              error("fail to add a filed. #{paramDef.name}, #{type_field}")
            end
            # add f_test Table
            if @database_parser.add_field(
                config.read("#{DB_F_TEST}_database_name"),
                config.read("#{DB_F_TEST}_database_tablename"),
                {field: "range_#{paramDef.name}", type: "Varchar(128)", null: "NO", key: "MUL"}
                                         ) < 0
              error("fail to add a filed. #{paramDef.name}, #{type_field}")
            end
            if @database_parser.add_field(
                config.read("#{DB_F_TEST}_database_name"),
                config.read("#{DB_F_TEST}_database_tablename"),
                {field: "f_value_of_#{paramDef.name}", type: "Float", null: "NO"}
                                         ) < 0
              error("fail to add a filed. #{paramDef.name}, #{type_field}")
            end
            if @database_parser.add_field(
                config.read("#{DB_F_TEST}_database_name"),
                config.read("#{DB_F_TEST}_database_tablename"),
                {field: "gradient_of_#{paramDef.name}", type: "Float", null: "NO"}
                                         ) < 0
              error("fail to add a filed. #{paramDef.name}, #{type_field}")
            end
          end
        end
        # >>>===
        database_check(config)
      end

      def create_node(arg_hash)
        connector = @connectors[:node]
        if (retval = connector.insert_record(arg_hash)).length != 0
          error("fail to add node. errno: #{retval}")
          return -1
        end
        return 0
      end

      def database_check(config)
        DATABASE_LIST.each do |name|
          # create a management database connector
          db = nil
          if (dbtype = config.read("#{name}_database_type")) == "mysql"
            db = Practis::Database::MysqlConnector.new(
                @database_parser.database_set,
                config.read("#{name}_database_hostname"),
                config.read("#{name}_database_management_username"),
                config.read("#{name}_database_management_password"))
          elsif dbtype == "mongo"
            db = Practis::Database::MongoConnector.new(
                @database_parser.database_set,
                config.read("#{name}_database_hostname"),
                config.read("#{name}_database_management_username"),
                config.read("#{name}_database_management_password"))
          else
            error("currently MySQL and Mongo are supported, but #{dbtype} is " +
                  "not supported.")
          end
          if db.nil?
            error("invalid database type: #{dbtype}")
            next
          end
          # create a database
          db_name = config.read("#{name}_database_name")
          if db.exist_database?(db_name)
            warn("database: #{db_name} already exists.")
          else
            if db.create_database(db_name) < 0
              error("fail to create database :#{db_name}")
              next
            end
          end
          if db.update_setting(db_name, config.read("#{name}_database_username")) < 0
            error("fail to set network config or authentification.")
            next
          end
          # create a table
          tbl_name = config.read("#{name}_database_tablename")
          if db.exist_table?(db_name, tbl_name)
            warn("table: #{tbl_name} already exist.")
          else
            if db.create_table(db_name, tbl_name) < 0
              error("fail to create table: #{tbl_name}.")
              next
            end
          end
          db.close
          case dbtype
          when "mysql"
            connectors[name.to_sym] = Practis::Database::MysqlConnector.new(
              @database_parser.database_set,
              config.read("#{name}_database_hostname"),
              config.read("#{name}_database_username"),
              config.read("#{name}_database_password"),
              config.read("#{name}_database_name"),
              config.read("#{name}_database_tablename"),
              config.read("database_query_retry").to_i
            )
          when "mongo"
            connectors[name.to_sym] = Practis::Database::MongoConnector.new(
              @database_parser.database_set,
              config.read("#{name}_database_hostname"),
              config.read("#{name}_database_username"),
              config.read("#{name}_database_password"),
              config.read("#{name}_database_name"),
              config.read("#{name}_database_tablename")
            )
          end
        end
      end

      def insert_record(type, arg_hash)
        if (connector = get_connector(type)).nil?
          error("invalid type: #{type}")
          return [nil]
        end
        connector.insert_record(arg_hash)
      end

      ##--------------------------------------------------
      ##--- read_record(type, [condition]) {|result| ...}
      ##    Send query to get data wrt condition.
      ##    If ((|&block|)) is given,  the block is called with 
      ##    ((|result|)) data of the query.
      ##    If ((|&block|)) is not given, it return an Array of the
      ##    result.
      def read_record(type, condition = nil, &block)
        if (connector = get_connector(type)).nil?
          error("invalid type: #{type}")
          return []
        end
        connector.read_record(condition,&block)
      end

      def inner_join_record(arg_hash)
#        debug(arg_hash)
        bcon = @connectors[arg_hash[:base_type]]
        rcon = @connectors[arg_hash[:ref_type]]
        condition = "#{rcon.database}.#{rcon.table} ON #{bcon.database}." +
              "#{bcon.table}.#{arg_hash[:base_field]} = #{rcon.database}." +
              "#{rcon.table}.#{arg_hash[:ref_field]}"
        # [2013/10/10 written by H-Matsushima]
        if arg_hash.key?(:condition)
          # condition += " WHERE #{arg_hash[:condition]}"
        end
        bcon.inner_join_record(condition, arg_hash[:condition])
      end

      def read_time(type = nil)
        type ||= :project
        connector = @connectors[type]
        timeval = nil
        unless (retval = connector.read({type: "runixtime"})).nil?
          retval.each { |r| r.values.each { |v| timeval = v.to_i } }
        end
        if timeval.nil?
          error("fail to get current time from the #{type} database.")
          return nil
        end
        return timeval
      end

      ## [2013/09/07 I.Noda]
      ##---read_max(type, record, valueType, condition)
      ##   retrieve max value of ((|record|)) in database ((|type|))
      ##   under ((|condition|)).
      ##   valueType is :integer, :float, or nil.
      def read_max(type, record, valueType, condition = nil)
        connector = @connectors[type]
        maxval = nil
        unless (retval = connector.read({type: "rmax", record: record},
                                        condition)).nil?
          retval.each { |r| r.values.each { |v| 
              maxval = (valueType == :integer ? v.to_i :
                        valueType == :float ? v.to_f :
                        v)
            }}
        end
        if maxval.nil?
          error("fail to get max value of #{record} from the #{type} database.")
          return nil
        end
        return maxval
      end

      ## [2013/09/08 I.Noda]
      ##---read_count(type, condition)
      ##   get count of data under ((|condition|)) in database ((|type|))
      def read_count(type, condition = nil)
        connector = @connectors[type]
        count = nil
        retval = connector.read({type: "rcount"},
                                condition){|retval|
          retval.each { |r| r.values.each { |v| count = v.to_i } }
        }
        if count.nil?
          error("fail to get count from the #{type} database.")
          return nil
        end
        return count
      end

      # [2013/11/25 H-Matsushima]
      def read_distinct_record(type, condition = nil)
        connector = @connectors[type]
        if !condition.nil?
          retval = connector.read({type: "rdiscrecord"}, condition){
            |retq|
            result = []
            return retq.nil? ? result : retq.inject(result) { |r, q| r << q }
          }
        else
          return []
        end
      end

      def register_project(project_name)
        connector = @connectors[:project]
        id = rand(MAX_PROJECT)
        if (retval = connector.read_record).length == 0
          while connector.insert_record(
              {project_id: id, project_name: project_name}).length != 0
            id = rand(MAX_PROJECT)
          end
        else
          ids = retval.select { |r| r["project_name"] == project_name }
          if ids.length != 1
            error("invalid project records")
            ids.each { |i| error(i) }
            return -1
          end
          id = ids[0]["project_id"]
        end
        return id
      end

      #=== check existing execution and register
      def register_execution(execution_name, project_id, executable_command)
        connector = @connectors[:execution]
        id = rand(MAX_EXECUTION)
#        if (retval = connector.read_record(
#            "project_id = #{project_id}")).length == 0
        if (retval = connector.read_record([:eq, [:field, "project_id"],
                                            project_id])).length == 0
          while connector.insert_record(
              {execution_id: id,
               execution_name: execution_name,
               project_id: project_id,
               executable_command: executable_command,
               execution_status: 'empty',
               execution_progress: 0.0,
               number_of_node: 0,
               number_of_parameter: 0,
               finished_parameter: 0,
               executing_parameter: 0}).length != 0
            id = rand(MAX_EXECUTION)
          end
        else
          #retval.each { |r| debug(r) }
          ids = retval.select { |r| r["execution_name"] == execution_name }
          if ids.length != 1
            error("invalid execution records")
            return -1
          end
          id = ids[0]["execution_id"]
        end
        return id
      end

      #=== check the node database.
      def check_previous_node_database(my_node_id, execution_id, address)
        connector = @connectors[:node]
        prev_nodes = []

        # check nodes of previous execution
        unless (retval = connector.read_record).length == 0
          retval.each do |r|
            node_id = r["node_id"]
            # If same id node exists, delete it.
            if my_node_id == node_id
#              unless (dretval = connector.delete_record(
#                  "node_id = #{my_node_id}")).nil?
              unless (dretval = 
                      connector.delete_record([:eq, [:field, "node_id"],
                                               my_node_id])).nil?
                dretval.each { |dr| warn(dr) }
              end
            else
#              unless (uretval = connector.update_record(
#                  {queueing: 0,
#                   executing: 0,
#                   state: NODE_STATE_FINISH},
#                  "node_id = #{node_id}")).nil?
              unless (uretval =
                      connector.update_record({ queueing: 0,
                                                executing: 0,
                                                state: NODE_STATE_FINISH},
                                              [:eq, [:field, "node_id"],
                                               node_id])).nil?
                uretval.each { |ur| warn(ur) }
              end
              prev_nodes << {parent: r["parent"], state: NODE_STATE_FINISH,
                node_type: r["node_type"], address: r["address"], id: node_id,
                parallel: r["parallel"]}
            end
          end
        end

        # register manager node
        if (ret = connector.insert_record(
            {node_id: my_node_id,
             node_type: NODE_TYPE_MANAGER,
             execution_id: execution_id,
             parent: 0,
             address: address,
             parallel: 1,
             queueing: 0,
             executing: 0,
             state: NODE_STATE_RUNNING})).length != 0
          error("fail to insert manager node.")
          ret.each { |r| error(r) }
        end
        return prev_nodes
      end

      #=== check the parameter and result database
      def check_previous_result_database
        rconnector = @connectors[:result]
        pconnector = @connectors[:parameter]
        results = rconnector.read_record
        parameters = pconnector.read_record
        finished_parameters = []
        finished_parameter_ids = []

        #[2013/09/24 I.Noda] for speed up
        parameterIdTable = {}
        parameters.each{|p|
          id = p["parameter_id"].to_i ;
          parameterIdTable[id] = (parameterIdTable[id] || Array.new).push(p) ;
        }

        results.each do |r|
#          ps = parameters.select { |p|
#            p["parameter_id"].to_i == r["result_id"].to_i }
          ps = parameterIdTable[r["result_id"].to_i] ;
          ps.each do |p|
            if p["state"] != PARAMETER_STATE_FINISH
#              unless (retval = pconnector.update_record(
#                  #{:state => PARAMETER_STATE_READY},
#                  {state: PARAMETER_STATE_FINISH},
#                  "parameter_id = #{r["result_id"].to_i}")).nil?
              unless (retval = 
                      pconnector.update_record({state: PARAMETER_STATE_FINISH},
                                               [:eq, [:field, "parameter_id"],
                                                r["result_id"].to_i])).nil?
                retval.each { |ret| warn(ret) }
              end
            end
            finished_parameters << p
            finished_parameter_ids << p["parameter_id"].to_i
          end
        end
        parameters.each do |p|
          if p["state"] != PARAMETER_STATE_FINISH &&
              !finished_parameter_ids.include?(p["parameter_id"].to_i)
#            unless (retval = pconnector.delete_record(
#                "parameter_id = #{p["parameter_id"].to_i}")).nil?
            unless (retval = 
                    pconnector.delete_record([:eq, [:field, "parameter_id"],
                                              p["parameter_id"].to_i])).nil?
              retval.each { |ret| warn(ret) }
            end
          end
        end
        return finished_parameters
      end

      def update_record(type, arg_hash, condition)
        if (connector = get_connector(type)).nil?
          error("invalid type: #{type}")
          return []
        end
        connector.update_record(arg_hash, condition)
      end

      def update_parameter(arg_hash, condition)
        connector = @connectors[:parameter]
        unless (retval = connector.update_record(arg_hash, condition)).nil?
          error("fail to update the parameter record.")
          retval.each { |r| error(r) }
          return -1
        end
        return 0
      end

      # [2013/09/08 I.Noda] !!!! need to improve.
      # most of operations in this methods should be done on DB,
      # instead of on-memory.
      def update_parameter_state(expired_timeout)
        pconnector = @connectors[:parameter]
        rconnector = @connectors[:result]
        finished_parameters = []
        if (timeval = read_time(:parameter)).nil?
          error("fail to get current time from the parameter database.")
          return nil, nil, nil, nil, nil
        end
        parameters = pconnector.read_record   # current executing parameters
        results = rconnector.read_record      # current stored results

        # count the number of the parameter each state.
        # [2013/09/24 I.Noda] change for speed up
        p_ready = p_alloc = p_execu = p_finis = 0 ;
        parameters.each{|p|
          case(p["state"])
          when PARAMETER_STATE_READY then p_ready += 1 ;
          when PARAMETER_STATE_ALLOCATING then p_alloc += 1 ;
          when PARAMETER_STATE_EXECUTING then p_execu += 1 ;
          when PARAMETER_STATE_FINISH then p_finis += 1 ;
          end
        }
#        p_ready = parameters.select { |p|
#          p["state"] == PARAMETER_STATE_READY }.length
#        p_alloc = parameters.select { |p|
#          p["state"] == PARAMETER_STATE_ALLOCATING }.length
#        p_execu = parameters.select { |p|
#          p["state"] == PARAMETER_STATE_EXECUTING }.length
#        p_finis = parameters.select { |p|
#          p["state"] == PARAMETER_STATE_FINISH }.length

        # [2013/09/24 I.Noda] change for speed up
        resultIdTable = {} ;
        results.each{|r|
          id = r["result_id"].to_i;
          resultIdTable[id] = (resultIdTable[id] || Array.new()).push(r)
        }

#        parameters.select { |p| p["state"] == PARAMETER_STATE_EXECUTING }
#            .each do |p|
        parameters.each do |p|
          next if (p["state"] != PARAMETER_STATE_EXECUTING) ;
#          if (results.select { |r| p["parameter_id"] == r["result_id"] })
#              .length > 0
          if(resultIdTable[p["parameter_id"].to_i]) then
#            if (retval = pconnector.update_record(
#                {state: PARAMETER_STATE_FINISH},
#                "parameter_id = #{p["parameter_id"]}")).length != 0
            if (retval = 
                pconnector.update_record({state: PARAMETER_STATE_FINISH},
                                         [:eq, [:field, "parameter_id"],
                                          p["parameter_id"]])).length != 0
              error("fail to update the parameter state")
              retval.each { |r| error(r) }
              next
            end
            p_execu -= 1
            p_finis += 1
            finished_parameters << p["parameter_id"].to_i
          else  # check the executing parameter is expired?
            if timeval - p["execution_start"].to_i > expired_timeout
#              if (retval = pconnector.update_record(
#                  {allocation_start: nil,
#                   execution_start: nil,
#                   state: PARAMETER_STATE_READY},
#                  "parameter_id = #{p["parameter_id"]}")).length != 0
              if (retval = 
                  pconnector.update_record({ allocation_start: nil,
                                             execution_start: nil,
                                             state: PARAMETER_STATE_READY},
                                           [:eq, [:field, "parameter_id"],
                                            p["parameter_id"]])).length != 0
                error("fail to update the expired parameter.")
                retval.each { |r| error(r) }
              end
              p_execu -= 1
              p_ready += 1
            end
          end
        end
        return p_ready, p_alloc, p_execu, p_finis, finished_parameters
      end

      def close
        DATABASE_LIST.each { |l| @connectors[l.to_sym].close }
      end

      private
      def get_connector(type)
        case type
        when :project then @connectors[:project]
        when :execution then @connectors[:execution]
        when :executable then @connectors[:executable]
        when :node then @connectors[:node]
        when :parameter then @connectors[:parameter]
        when :result then @connectors[:result]
        when :orthogonal then @connectors[:orthogonal]
        when :f_test then @connectors[:f_test]
        else nil
        end
      end

      def create(type, arg_hash, condition)
        if (conn = get_connector(type)).nil?
          error("invalid database type.")
          return nil
        end
        return conn.create(arg_hash, condition)
      end

      def read(type, arg_hash, condition)
        if (conn = get_connector(type)).nil?
          error("invalid database type.")
          return nil
        end
        return conn.read(arg_hash, condition)
      end

      def update(type, arg_hash, condition)
        if (conn = get_connector(type)).nil?
          error("invalid database type.")
          return nil
        end
        return conn.update(arg_hash, condition)
      end

      def delete(type, arg_hash, condition)
        if (conn = get_connector(type)).nil?
          error("invalid database type.")
          return nil
        end
        return conn.delete(arg_hash, condition)
      end
    end

    #=== MySQL database connector.
    #Simple mysql database connection functionality is provided with this class.
    class MysqlConnector

      include Practis

      attr_reader :command_generator
      attr_reader :hostname, :username, :database, :table

      #def initialize
      #query_retry :: if SQL failed, how many times it retry the query. if this
      #value is negative, it eternally retries.
      def initialize(schema, hostname, username, password, database = nil,
                     table = nil, query_retry = QUERY_RETRY_TIMES)
        @command_generator = Practis::Database::MysqlCommandGenerator.new(
          schema)
        @hostname = hostname
        @username = username
        @password = password
        @database = database
        @table = table
        @query_retry = query_retry
        ##<<<[2013/09/04 I.Noda]
        ## for exclusive connection use
        @mutex = Mutex.new() ;
        ##>>>[2013/09/04 I.Noda]
        connect
      end

      #=== Specified database exist? or not.
      #database :: database name.
      #returned_value :: If exist, it returns true. Otherwise, it returns false.
      def exist_database?(database)
        unless (retval = query(@command_generator.get_command(
            nil, nil, {type: "rdatabase"}))).nil?
          return  retval.inject(false) { |b, r| b || r["Database"] == database }
        end
        return false
      end

      def exist_table?(database, table)
        unless (retval = query(@command_generator.get_command(
            database, nil, {type: "rtable"}))).nil?
          return  retval.inject(false) { |b, r|
            b || r["Tables_in_#{database}"] == table }
        end
        return false
      end

      def exist_record?(key, value)
        if (retval = query(@command_generator.get_command(
            @database, @table, {type: "rrecord"}))).nil?
          debug("specified table has no record.")
        else
          retval.each do |r|
            if r[key] == value
              return true
            end
          end
        end
        return false
      end

      def create_database(database)
        # create database
        unless (retval = query(@command_generator.get_command(
            database, nil, {type: "cdatabase"}))).nil?
          warn("fail to create database: #{database}")
          retval.each { |r| warn(r) }
          return -1
        end
        return 0
      end

      def update_setting(database, username)
        # set network configuration
        unless (retval = query(@command_generator.get_command(
            database, nil, {type: "uglobal"}))).nil?
          warn("fail to set global options to database: #{database}.")
          retval.each { |r| warn(r) }
          return -1
        end
        # set authentification
        unless (retval = query(@command_generator.get_command(
            database, nil, {type: "cgrant", username: username}))).nil?
          warn("fail to set grant global option to database: #{database}.")
          retval.each { |r| warn(r) }
          return -2
        end
        unless (retval = query(@command_generator.get_command(
          database, nil, {type: "cgrantl", username: username}))).nil?
          warn("fail to set grant local option to database: #{database}.")
          retval.each { |r| warn(r) }
          return -3
        end
        return 0
      end

      def create_table(database, table)
        com = @command_generator.get_command(database, table, 
                                             {type: "ctable"}) ;
#        debug("create_table:com=#{com}") ;
        unless (retval = query(com)).nil?
          warn("fail to create table: #{table}.")
          retval.each { |r| warn(r) }
          return -1
        end
        return 0
      end

      def insert_record(arg_hash)
        arg_hash[:type] = "cinsert"
        # <<< [2013/09/05 I.noda]
        #retq = query(@command_generator.get_command(
        #  @database, @table, arg_hash))
        #retq.nil? ? [] : retq.inject([]) { |r, q| r << q }
        query(@command_generator.get_command(@database, @table, arg_hash)){
          |retq|
          return retq.nil? ? [] : retq.inject([]) { |r, q| r << q }
        }
        # >>> [2013/09/05 I.noda]
      end

      ##--------------------------------------------------
      ##--- read_record([condition]) {|result| ...}
      ##    send query to get data wrt condition.
      ##    If ((|&block|)) is given,  the block is called with 
      ##    ((|result|)) data of the query.
      ##    If ((|&block|)) is not given, it return an Array of the
      ##    result.
      def read_record(condition = nil,&block)
        # <<< [2013/09/05 I.noda]
        #retq = query(@command_generator.get_command(
        #  @database, @table, {type: "rrecord"}, condition))
        #retq.nil? ? [] : retq.inject([]) { |r, q| r << q }
        # [2013/09/08 I.Noda] use Array.new instead of [] for safety.
        if(block.nil?)
          query(@command_generator.get_command(@database, @table, 
                                               {type: "rrecord"}, condition)){
            |retq|
            result = Array.new()
            return retq.nil? ? result : retq.inject(result) { |r, q| r << q }
          }
        else
          query(@command_generator.get_command(@database, @table, 
                                               {type: "rrecord"}, condition),
                &block) ;
        end
        # <<< [2013/09/05 I.noda]
      end

      def delete_record(condition = nil)
        # <<< [2013/09/05 I.noda]
        #retq = query(@command_generator.get_command(
        #  @database, @table, {type: "drecord"}, condition))
        #retq.nil? ? [] : retq.inject([]) { |r, q| r << q }
        query(@command_generator.get_command(@database, @table, 
                                             {type: "drecord"}, condition)){
          |retq|
          return retq.nil? ? [] : retq.inject([]) { |r, q| r << q }
        }
        # <<< [2013/09/05 I.noda]
      end

      def update_record(arg_hash, condition = nil)
        arg_hash[:type] = "urecord"
        # <<< [2013/09/05 I.noda]
        #retq = query(@command_generator.get_command(
        #  @database, @table, arg_hash, condition))
        #retq.nil? ? [] : retq.inject([]) { |r, q| r << q }
        query(@command_generator.get_command(@database, @table, 
                                             arg_hash, condition)){
          |retq|
          return retq.nil? ? [] : retq.inject([]) { |r, q| r << q }
        }
        # <<< [2013/09/05 I.noda]
      end

      def inner_join_record(condition = nil, where = nil)
        # <<< [2013/09/05 I.noda]
        #retq = query(@command_generator.get_command(
        #  @database, @table, {type: "rinnerjoin"}, condition))
        #retq.nil? ? [] : retq.inject([]) { |r, q| r << q }
        conditions = [condition, where]
        # condition += "#{@command_generator.condition_to_sql(@database, @table, where)}"
        # pp condition
        query(@command_generator.get_command(@database, @table, 
                                             {type: "rinnerjoin"}, conditions)){
          |retq|
          return retq.nil? ? [] : retq.inject([]) { |r, q| r << q }
        }
        # <<< [2013/09/05 I.noda]
      end

      def read(arg_hash, condition = nil, &block)
        com = @command_generator.get_command(@database, @table, 
                                             arg_hash, condition)
#        info(arg_hash.inspect) ;
#        info(com) ;
        query(com,  &block)
      end

      #=== Close the database connection.
      def close
        begin
          @connector.close
        rescue Exception => e
          error("failed to close the database connection. #{e.message}")
          error(e.backtrace)
          raise e
        end
      end

      private
      #=== Connect to the database.
      def connect
        begin
          if @database
            @connector = Mysql2::Client::new(
              host: @hostname,
              username: @username,
              password: @password,
              database: @database
                                            )
          else
            @connector = Mysql2::Client::new(
              host: @hostname,
              username: @username,
              password: @password
                                            )
          end
        rescue Exception => e
          error("failed to connect database. #{e.message}")
          error(e.backtrace)
          raise e
        end
      end

      #=== Execute a query.
      #query_string :: mysql query.
      #returned value :: Mysql2 Result objects.
      def query(query_string, option = nil, &block)
        c = @query_retry
        while true
          @mutex.synchronize(){  ###<<<[2013/09/04 I.Noda] for exclusive call>>>
            begin
              ## <<< [2013/09/05 I.Noda]
              ## to introduce block call
              res = nil ;
              if option.nil?
                res = @connector.query(query_string)
              else
                res = @connector.query(query_string, option)
              end
              if(block) then
                return block.call(res) ;
              else
                return res ;
              end
              ## >>> [2013/09/05 I.Noda]
            rescue Mysql2::Error => e
              error("failed to run query. #{e.message}")
              error("failed query: #{query_string}")
              error(e.backtrace)
              sleep(QUERY_RETRY_DURATION)
              raise e if c == 0
            end
          } ###<<<[2013/09/04 I.Noda]>>>
          c -= 1
          end
      end

      def create(type, arg_hash, condition)
        if (conn = get_connector(type)).nil?
          error("invalid database type.")
          return nil
        end
        return conn.create(arg_hash, condition)
      end
    end

    class MongoConnector
    end
  end
end
