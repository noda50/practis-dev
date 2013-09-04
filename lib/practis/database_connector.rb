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

      def setup_database(variable_set, result_set, config)
        # add parameter fields to parameter table
        variable_set.each do |v|
          if (type_field = type_to_sqltype(v.type.to_s)).nil?
            error("type field requires any types. #{v}")
            next
          end
          if @database_parser.add_field(
              config.read("#{DB_PARAMETER}_database_name"),
              config.read("#{DB_PARAMETER}_database_tablename"),
              {field: v.name, type: type_field, null: "NO"}
                                       ) < 0
            error("fail to add a filed. #{v.name}, #{type_field}")
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
        database_check(config)
      end

      def create_node(arg_hash)
        connector = @connectors[:node]
        if (retval = connector.insert_column(arg_hash)).length != 0
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
            debug("database: #{db_name} already exists.")
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
            debug("table: #{tbl_name} aldready exist.")
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

      def insert_column(type, arg_hash)
        if (connector = get_connector(type)).nil?
          error("invalid type: #{type}")
          return [nil]
        end
        connector.insert_column(arg_hash)
      end

      def read_column(type, condition = nil)
        if (connector = get_connector(type)).nil?
          error("invalid type: #{type}")
          return []
        end
        connector.read_column(condition)
      end

      def inner_join_column(arg_hash)
        debug(arg_hash)
        bcon = @connectors[arg_hash[:base_type]]
        rcon = @connectors[arg_hash[:ref_type]]
        condition = "#{rcon.database}.#{rcon.table} ON #{bcon.database}." +
              "#{bcon.table}.#{arg_hash[:base_field]} = #{rcon.database}." +
              "#{rcon.table}.#{arg_hash[:ref_field]}"
        bcon.inner_join_column(condition)
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

      def register_project(project_name)
        connector = @connectors[:project]
        id = rand(MAX_PROJECT)
        if (retval = connector.read_column).length == 0
          while connector.insert_column(
              {project_id: id, project_name: project_name}).length != 0
            id = rand(MAX_PROJECT)
          end
        else
          ids = retval.select { |r| r["project_name"] == project_name }
          if ids.length != 1
            error("invalid project columns")
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
        if (retval = connector.read_column(
            "project_id = #{project_id}")).length == 0
          while connector.insert_column(
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
            error("invalid execution columns")
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
        unless (retval = connector.read_column).length == 0
          retval.each do |r|
            node_id = r["node_id"]
            # If same id node exists, delete it.
            if my_node_id == node_id
              unless (dretval = connector.delete_column(
                  "node_id = #{my_node_id}")).nil?
                dretval.each { |dr| warn(dr) }
              end
            else
              unless (uretval = connector.update_column(
                  {queueing: 0,
                   executing: 0,
                   state: NODE_STATE_FINISH},
                  "node_id = #{node_id}")).nil?
                uretval.each { |ur| warn(ur) }
              end
              prev_nodes << {parent: r["parent"], state: NODE_STATE_FINISH,
                node_type: r["node_type"], address: r["address"], id: node_id,
                parallel: r["parallel"]}
            end
          end
        end

        # register manager node
        if (ret = connector.insert_column(
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
        results = rconnector.read_column
        parameters = pconnector.read_column
        finished_parameters = []
        finished_parameter_ids = []

        results.each do |r|
          ps = parameters.select { |p|
            p["parameter_id"].to_i == r["result_id"].to_i }
          ps.each do |p|
            if p["state"] != PARAMETER_STATE_FINISH
              unless (retval = pconnector.update_column(
                  #{:state => PARAMETER_STATE_READY},
                  {state: PARAMETER_STATE_FINISH},
                  "parameter_id = #{r["result_id"].to_i}")).nil?
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
            unless (retval = pconnector.delete_column(
                "parameter_id = #{p["parameter_id"].to_i}")).nil?
              retval.each { |ret| warn(ret) }
            end
          end
        end
        return finished_parameters
      end

      def update_column(type, arg_hash, condition)
        if (connector = get_connector(type)).nil?
          error("invalid type: #{type}")
          return []
        end
        connector.update_column(arg_hash, condition)
      end

      def update_parameter(arg_hash, condition)
        connector = @connectors[:parameter]
        unless (retval = connector.update_column(arg_hash, condition)).nil?
          error("fail to update the parameter column.")
          retval.each { |r| error(r) }
          return -1
        end
        return 0
      end

      def update_parameter_state(expired_timeout)
        pconnector = @connectors[:parameter]
        rconnector = @connectors[:result]
        finished_parameters = []
        if (timeval = read_time(:parameter)).nil?
          error("fail to get current time from the parameter database.")
          return nil, nil, nil, nil, nil
        end
        parameters = pconnector.read_column   # current executing parameters
        results = rconnector.read_column      # current stored results

        # count the number of the parameter each state.
        p_ready = parameters.select { |p|
          p["state"] == PARAMETER_STATE_READY }.length
        p_alloc = parameters.select { |p|
          p["state"] == PARAMETER_STATE_ALLOCATING }.length
        p_execu = parameters.select { |p|
          p["state"] == PARAMETER_STATE_EXECUTING }.length
        p_finis = parameters.select { |p|
          p["state"] == PARAMETER_STATE_FINISH }.length
        parameters.select { |p| p["state"] == PARAMETER_STATE_EXECUTING }
            .each do |p|
          if (results.select { |r| p["parameter_id"] == r["result_id"] })
              .length > 0
            if (retval = pconnector.update_column(
                {state: PARAMETER_STATE_FINISH},
                "parameter_id = #{p["parameter_id"]}")).length != 0
              error("fail to update the parameter state")
              retval.each { |r| error(r) }
              next
            end
            p_execu -= 1
            p_finis += 1
            finished_parameters << p["parameter_id"].to_i
          else  # check the executing parameter is expired?
            if timeval - p["execution_start"].to_i > expired_timeout
              if (retval = pconnector.update_column(
                  {allocation_start: nil,
                   execution_start: nil,
                   state: PARAMETER_STATE_READY},
                  "parameter_id = #{p["parameter_id"]}")).length != 0
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

      def exist_column?(key, value)
        if (retval = query(@command_generator.get_command(
            @database, @table, {type: "rcolumn"}))).nil?
          debug("specified table has no column.")
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
        unless (retval = query(@command_generator.get_command(
            database, table, {type: "ctable"}))).nil?
          warn("fail to create table: #{table}.")
          retval.each { |r| warn(r) }
          return -1
        end
        return 0
      end

      def insert_column(arg_hash)
        arg_hash[:type] = "cinsert"
        retq = query(@command_generator.get_command(
          @database, @table, arg_hash))
        retq.nil? ? [] : retq.inject([]) { |r, q| r << q }
      end

      def read_column(condition = nil)
        retq = query(@command_generator.get_command(
          @database, @table, {type: "rcolumn"}, condition))
        retq.nil? ? [] : retq.inject([]) { |r, q| r << q }
      end

      def delete_column(condition = nil)
        retq = query(@command_generator.get_command(
          @database, @table, {type: "dcolumn"}, condition))
        retq.nil? ? [] : retq.inject([]) { |r, q| r << q }
      end

      def update_column(arg_hash, condition = nil)
        arg_hash[:type] = "ucolumn"
        retq = query(@command_generator.get_command(
          @database, @table, arg_hash, condition))
        retq.nil? ? [] : retq.inject([]) { |r, q| r << q }
      end

      def inner_join_column(condition = nil)
        retq = query(@command_generator.get_command(
          @database, @table, {type: "rinnerjoin"}, condition))
        retq.nil? ? [] : retq.inject([]) { |r, q| r << q }
      end

      def read(arg_hash, condition = nil)
        query(@command_generator.get_command(
          @database, @table, arg_hash, condition))
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
      def query(query_string, option = nil)
        c = @query_retry
        while true
          @mutex.synchronize(){  ###<<<[2013/09/04 I.Noda] for exclusive call>>>
            begin
              if option.nil?
                return @connector.query(query_string)
              else
                return @connector.query(query_string, option)
              end
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
