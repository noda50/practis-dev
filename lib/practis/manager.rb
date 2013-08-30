#!/usr/bin/ruby
# -*- coding: utf-8 -*-

require 'rubygems'
require 'json'
#require 'thread'

require 'practis/cluster'
require 'practis/daemon'
require 'practis/database_connector'
require 'practis/message_handler'
require 'practis/net'
require 'practis/parameter_parser'
require 'practis/result_parser'

module Practis

  #=== Manager of practis.
  class Manager < Practis::Daemon

    # message handler
    attr_reader :message_handler
    # variables definition with VariableSet class.
    attr_reader :variable_set
    # store parameters that once allocated, but returned or quited.
    attr_accessor :parameter_pool

    # current project id
    attr_reader :project_id
    # current execution id
    attr_reader :execution_id

    # keep alive expired duration
    attr_reader :keepalive_expired_duration
    #  query storing the result executed on an Executor.
    #attr_reader :result_accessor
    # Field names of the result
    attr_reader :result_fields
    attr_reader :executable_command
    attr_reader :executable_path
    attr_reader :database_connector

    attr_reader :finished_parameters

    def initialize(config_file, parameter_file, database_file, result_file,
                   myaddr = nil)
      super(config_file)

      # initialize message handler
      if (duration = @config.read("message_handler_duration").to_i).nil?
          duration = DEFAULT_MESSAGE_HANDLER_DURATION
      end
      @message_handler = MessageHandler.new(self, duration)
      debug("Message handler is initialized")

      # create a cluster tree and set manager node into the tree.
      @cluster_tree = Practis::ClusterTree.new

      # get_my_address just gets an IP address from hostname. if your cluster
      # has multiple network interfaces, be careful not to choose unexpected
      # address.
      myaddr ||= get_my_address
      debug("Manager address is #{myaddr}")
      @mynode = cluster_tree.create(nil, NODE_TYPE_MANAGER, myaddr, 1)
      if @mynode.nil?
        error("fail to create valid cluster tree. My address is not known.")
        raise RuntimeError
        finalize
      end

      # keepalive duration
      if (@keepalive_duration = @config.read("keepalive_duration").to_i).nil?
        @keepalive_duration = DEFAULT_KEEPALIVE_DURATION
      end
      if (@keepalive_expired_duration = @config.read(
          "keepalive_expired_duration").to_i).nil?
        @keepalive_expired_duration = DEFAULT_KEEPALIVE_EXPIRED_DURATION
      end

      # timeout seconds that an executing parameter timeout.
      if (@parameter_allocation_expired_timeout =
          @config.read("parameter_allocation_expired_timeout").to_i).nil?
        @parameter_allocation_expired_timeout = DEFAULT_PARAMETER_EXPIRED_TIMEOUT
      end
      if (@parameter_execution_expired_timeout =
          @config.read("parameter_execution_expired_timeout").to_i).nil?
        @parameter_execution_expired_timeout = DEFAULT_PARAMETER_EXPIRED_TIMEOUT
      end

      # create database connector
      @database_connector = Practis::Database::DatabaseConnector.new(
        database_file)

      # Parse and set simulation parameters
      pparser = Practis::Parser::ParameterParser.new(parameter_file)
      if pparser.parse < 0
        error("failed to parse parameter file.")
        finalize
      end
      debug(pparser.print_variables)
      if (scheduler_name = @config.read("parameter_scheduler")).nil?
        @variable_set = Practis::VariableSet.new(pparser.variable_set)
      else
        @variable_set = Practis::VariableSet.new(pparser.variable_set,
                                                 scheduler_name)
      end
      # parse result configuration
      rparser = Practis::Parser::ResultParser.new(result_file)
      rparser.parse
      debug("results: #{rparser.result_set}")

      # set up the databases.
      @database_connector.setup_database(@variable_set.variable_set,
                                         rparser.result_set, @config)

      # Register current project to DB.
      @project_name = @config.read("project_name")
      if (@project_id = @database_connector.register_project(@project_name)) < 0
        error("fail to register project: #{@project_name}")
        finalize
      end

      # Register current execution to DB.
      @execution_name = @config.read("execution_name")
      @executable_command = create_executable_command
      @execution_id = @database_connector.register_execution(
        @execution_name, @project_id, @executable_command)

      # check previous execution parameters and results
      @database_connector.check_previous_node_database(
          @mynode.id, @execution_id, @mynode.address).each do |pnode|
        @cluster_tree.id_pool << pnode[:id]
      end
      @database_connector.check_previous_result_database.each do |p|
      end

      @executable_path = @config.read("executable_path")

      @result_fields = []
      rparser.result_set.each do |r|
        @result_fields.push({name: r[0], type: r[1]})
      end
      debug("loaded result fields: #{@result_fields}")
      @parameter_pool = []

      # KeepAlive Handler
      error("fail to create KeepAliveHandler") if @message_handler
        .createHandler("KeepAliveHandler", get_srv_sock(KEEP_ALIVE_PORT)) < 0
      # JoinPractis Handler
      error("fail to create JoinPractisHandler") if @message_handler
        .createHandler("JoinPractisHandler",
                       get_srv_sock(JOIN_PRACTIS_PORT)) < 0
      # ReqExecutable Handler
      error("fail to create ReqExecutableHandler") if @message_handler
        .createHandler("ReqExecutableHandler",
                       get_srv_sock(REQ_EXECUTABLE_PORT)) < 0
      # ReqParameter Handler
      error("fail to create ReqParameterHandler") if @message_handler
        .createHandler("ReqParametersHandler",
                       get_srv_sock(REQ_PARAMETERS_PORT)) < 0
      # UploadResult Handler
      error("fail to create UploadResultHandler") if @message_handler
        .createHandler("UploadResultHandler",
                       get_srv_sock(UPLOAD_RESULT_PORT)) < 0
      # StartExecution Handler
      error("fail to create StartExecutionHandler") if @message_handler
        .createHandler("StartExecutionHandler",
                       get_srv_sock(START_EXECUTION_PORT)) < 0
      debug("Manager initialized.")
    end

    #=== generate executable command.
    def create_executable_command
      executable_command = String.new
      executable_command << @config.read("executable_command")
      if executable_command == ""
        executable_command += "%s" % @config.read("executable")
        count = 1
        while !(cmd_arg = @config.read("executable_arg#{count}")).nil?
          executable_command += " %s" % cmd_arg
          count += 1
        end
      end
      return executable_command
    end

    #Determine where the new node is put into the tree.
    def allocate_node(node_type, address, id=nil, parallel=nil)
      # Temporaly simple star topology.
      debug("node is create")
      return nil if (node = cluster_tree.create(mynode, node_type, address, id,
                                                parallel)).nil?
      debug("node #{node.to_s}")
      partial_tree = cluster_tree.get_partial_tree(node.id)
      # register the node
      if @database_connector.create_node(
          {node_id: partial_tree.mynode[:id],
           node_type: NODE_TYPE_EXECUTOR,
           execution_id: @execution_id,
           parent: @mynode.id,
           address: address,
           parallel: parallel,
           queueing: 0,
           executing: 0,
           state: NODE_STATE_READY}) < 0
        error("fail to add new node on database.")
        return nil
      end
      return partial_tree
    end

    #=== Allocate requested number of parameters.
    def allocate_parameters(request_number, src_id)
      parameters = []   # allocated parameters
      if (timeval = @database_connector.read_time(:parameter)).nil?
        return nil
      end
      # get the parameter with 'ready' state.
      if (p_ready = @database_connector.read_column(
          :parameter, "state = '#{PARAMETER_STATE_READY}'")).length > 0
        p_ready.each do |p|
          break if request_number <= 0
          if (matches = @parameter_pool.select { |pp|
              p["parameter_id"].to_i == pp.uid }).length == 1
            # update the allocating parameter state
            if @database_connector.update_parameter(
                {allocated_node_id: src_id,
                 executing_node_id: src_id,
                 allocation_start: iso_time_format(timeval),
                 execution_start: nil,
                 state: PARAMETER_STATE_ALLOCATING},
                "parameter_id = #{p["parameter_id"].to_i}") < 0
              error("failt to update the parameter with 'ready' state.")
            else
              matches[0].state = PARAMETER_STATE_ALLOCATING
              parameters.push(matches[0])
              request_number -= 1
            end
            next
          end
        end
      end

      # generate the parameters from the scheduler
      while request_number > 0
        if (parameter = @variable_set.get_next).nil?
          info("all parameter is already allocated!")
          break
        end
        condition = parameter.parameter_set.map { |p|
          "#{p.name} = '#{p.value}'" }.join(" and ")
        debug(condition)
        if (retval = @database_connector.read_column(
            :parameter, condition)).length == 0
          arg_hash = {parameter_id: parameter.uid,
                      allocated_node_id: src_id,
                      executing_node_id: src_id,
                      allocation_start: iso_time_format(timeval),
                      execution_start: nil,
                      state: PARAMETER_STATE_ALLOCATING}
          parameter.parameter_set.each { |p|
            arg_hash[(p.name).to_sym] = p.value }
          if @database_connector.insert_column(:parameter, arg_hash).length != 0
            error("fail to insert a new parameter.")
          else
            parameter.state = PARAMETER_STATE_ALLOCATING
            parameters.push(parameter)
            @parameter_pool.push(parameter)
            request_number -= 1
          end
        else
          info("the parameter already executed on previous or by the others.")
          info("condition: #{condition}")
          retval.each do |r|
            info(r)
            parameter.state = r["state"]
            @parameter_pool.push(parameter)
          end
          next
        end
      end
      return parameters
    end

    #=== update the started parameter state.
    def update_started_parameter_state(parameter_id, executor_id)
      if (timeval = @database_connector.read_time(:parameter)).nil?
        return -1
      end
      if (retval = @database_connector.update_column(
          :parameter,
          {state: PARAMETER_STATE_EXECUTING,
           execution_start: iso_time_format(timeval),
           execution_node_id: executor_id},
          "parameter_id = #{parameter_id}")).length != 0
        error("fail to update the started parameter state. #{retval}")
        return -1
      end
      return 0
    end

    #=== update the node state on node database.
    #node_id :: node id
    #queueing :: a number of queueing parameter
    #executing :: a number of executing parameter
    #returned_value :: On success, 0 is returned. On error, a negative value is
    #returned.
    def update_node_state(node_id, queueing, executing)
      if (retval = @database_connector.update_column(
          :node,
          {queueing: queueing,
           executing: executing,
           state: NODE_STATE_RUNNING},
           "node_id = #{node_id}")).length != 0
        error("fail to update the node state. #{retval}")
        return -1
      end
      return 0
    end

    def upload_result(msg)
      result_id = msg[:result_id].to_i
      if (retval = @database_connector.read_column(
          :result, "result_id = #{result_id}")).length != 0
        error("the result already exist. #{retval}")
        return -1
      end
      arg_hash = {result_id: msg[:result_id],
                  execution_time: msg[:execution_time]}
      @result_fields.each do |f|
        #debug("f: #{f}, msg[:fields]: #{msg[:fields]}")
        arg_hash[f[:name].to_sym] = msg[:fields][f[:name].to_sym]
      end
      #debug(arg_hash)
      if (retval = @database_connector.insert_column(
          :result, arg_hash)).length != 0
        error("fail to insert the new result. #{retval}")
        return -2
      end
      return 0
    end

    def update
      cluster_tree.root.children.each do |child|
        decrease_keepalive(child)
      end
      ready_n, allocating_n, executing_n, @finished_parameters,
        current_finished = @database_connector.update_parameter_state(
          @parameter_execution_expired_timeout)
      current_finished.each do |finished_id|
        @parameter_pool.each do |p|
          if p.uid == finished_id
            @parameter_pool.delete(p)
            break
          end
        end
      end
      @total_parameters = @variable_set.get_total
      debug(cluster_tree.to_s)
      info("not allocated parameters: #{@variable_set.get_available}, " +
           "ready: #{ready_n}, " +
           "allocating: #{allocating_n}, " +
           "executing: #{executing_n}, " +
           "finish: #{@finished_parameters}, " +
           "total: #{@total_parameters}")
      unless @message_handler.alive?
        warn("message_handler not alive")
        @message_handler.join
      end
      # All parameters are finished, finalize
      if @total_parameters <= @finished_parameters
        # check
        if @variable_set.get_available <= 0 and @parameter_pool.length <= 0
          if (retval = allocate_parameters(1, 1)).length == 0
            retval.each {|r| debug("#{r}")}
            finalize
          else
            error("all parameter is finished? Huh???")
          end
        end
      end
    end

    def decrease_keepalive(node)
      if node.keepalive < 0
        cluster_tree.delete(:id, node.id)
        if (retval = @database_connector.update_column(
            :node,
            {queueing: 0,
             executing: 0,
             state: NODE_STATE_TIMEOUT},
            "node_id = #{node.id}")).length > 0
          retval.each { |r| error(r) }
        end
      else
        node.keepalive -= loop_sleep_duration
      end
      node.children.each do |child|
        decrease_keepalive(child)
      end
    end

    def finalize
      info("Manager finalizing process")
      begin
        @database_connector.close
      rescue Exception => e
        error("fail to close database connection. #{e.message}")
        error(e.backtrace)
      end
      unless @message_handler.nil?
        @message_handler.running = false
        @message_handler.join
      end
      info("Manager finished")
      info(Time.now - start_time)
      super
    end

    #=== provide the cluster tree in JSON object.
    def get_cluster_json
      hash = nil
      parent_id = @mynode.id
      if (retval = @database_connector.read_column(:node)).length > 0
        retval.each do |r|
          if r["node_id"] == @mynode.id
            hash = {node_id: @mynode.id,
                    node_type: r["node_type"],
                    execution_id: r["execution_id"],
                    address: r["address"],
                    parent: r["parent"],
                    parallel: r["parallel"],
                    queueing: r["queueing"],
                    executing: r["executing"],
                    state: r["state"],
                    finished: @finished_parameters,
                    total: @total_parameters}
          end
        end
      end
      if hash.nil?
        error("manager does not exist on node database.")
        return nil
      end
      hash[:children] = get_cluster_children(parent_id, retval)
      json = nil
      begin
        json = JSON.generate(hash)
        return json
      rescue Exception => e
        error("fail to generate cluster tree json. #{e.message}")
        error(e.backtrace)
      end
      return nil
    end

    def get_parameter_progress
      finished = nil
      if (retval = @database_connector.read_column(
          :parameter, "state = #{PARAMETER_STATE_FINISH}")).length > 0
        finished = retval
      end
      hash = {}
      total = @variable_set.get_total
      hash[:total_parameters] = total
      hash[:finished_parameters] = @finished_parameters
      va = []
      @variable_set.variable_set.each do |v|
        va.push({:name => v.name, :values => v.parameters})
      end
      hash[:variables] = va
      pa = []
      hash[:progress] = pa
      l = @variable_set.variable_set.length
      (0..l - 2).each do |i|
        (i + 1..l - 1).each do |j|
          v1 = @variable_set.variable_set[i]
          v2 = @variable_set.variable_set[j]
          hash_progress = {}
          hash_progress[:variable_pair] = [v1.name, v2.name]
          hash_progress[:total] = total / v1.parameters.length / \
              v2.parameters.length
          efa = []
          v1.parameters.each do |p1|
            v2.parameters.each do |p2|
              count = 0
              finished.each do |f|
                if f[v1.name] == p1 and f[v2.name] == p2
                  count += 1
                end
              end
              efa.push({:value => [p1, p2], :finish => count})
            end
          end
          hash_progress[:each_finish] = efa
          pa.push(hash_progress)
        end
      end
      begin
        json = JSON.generate(hash)
        return json
      rescue Exception => e
        error("fail to generate parameter progress json. #{e.message}")
        error(e.backtrace)
      end
      return nil
    end

    #=== generate the result in JSON.
    def get_results
      hash = {}
      hash[:parameters] = @variable_set.variable_set.map {|v| v.name}
      hash[:results] = @result_fields.map { |f| f[:name] }
      hash[:results].push("execution_time")
      result_data = []
      if (retval = @database_connector.inner_join_column(
          {base_type: :result, ref_type: :parameter,
           base_field: :result_id, ref_field: :parameter_id})).length > 0
        retval.each do |r|
          debug("#{r}")
          rhash = {}
          rhash[:id] = r["result_id"]
          phash = {}
          hash[:parameters].each do |p|
            phash[p.to_sym] = r[p]
          end
          reshash = {}
          reshash[:execution_time] = r["execution_time"]
          hash[:results].each do |res|
            reshash[res.to_sym] = r[res]
          end
          rhash[:parameter] = phash
          rhash[:result] = reshash
          result_data.push(rhash)
        end
      end
      hash[:result_data] = result_data
      debug(hash)
      json = JSON.generate(hash)
      return json
    end

    private
    def get_cluster_children(parent_id, mysql_results)
      a = []
      mysql_results.each do |r|
        if r["parent"] == parent_id
          hash = {:node_id => r["node_id"], :execution_id => r["execution_id"],
                  :node_type => r["node_type"],
                  :address => r["address"], :parent => r["parent"],
                  :parallel => r["parallel"], :queueing => r["queueing"],
                  :executing => r["executing"], :state => r["state"]}
          hash[:children] = get_cluster_children(r["node_id"], mysql_results)
          a.push(hash)
        end
      end
      return a
    end
  end
end
