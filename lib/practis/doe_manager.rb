#!/usr/bin/ruby
# -*- coding: utf-8 -*-

require 'rubygems'
require 'json'
require 'bigdecimal'
require 'matrix'
require 'csv'
require 'pp'

# require 'thread'

require 'practis/cluster'
require 'practis/daemon'
require 'practis/database_connector'
require 'practis/message_handler'
require 'practis/net'
require 'practis/parameter_parser'
require 'practis/result_parser'


require 'doe/orthogonal_array'
require 'doe/orthogonal_table'
require 'doe/variance_analysis'
require 'doe/f_distribution_table'
require 'doe/regression'

module Practis

  class DoeManager < Practis::Manager
    include Regression
    include OrthogonalTable

    attr_reader :va_queue
    attr_reader :current_var_set

    def initialize(config_file, parameter_file, database_file, result_file, doe_conf, myaddr = nil)
      @doe_definitions = nil
      open(doe_conf, 'r'){|fp|
        @doe_definitions = JSON.parse(fp.read)
      }
      super(config_file, parameter_file, database_file, result_file, myaddr, @doe_definitions)

      otable = generation_orthogonal_table(@paramDefSet.paramDefs)
      @paramDefSet = Practis::ParamDefSet.new(@paramDefSet.paramDefs, "DOEScheduler")
      @scheduler = @paramDefSet.scheduler.scheduler
      @scheduler.init_doe(@database_connector, otable, @doe_definitions)
      
      @total_parameters = @paramDefSet.get_total

      @f_disttable = F_DistributionTable.new(0.01)
    end

    ## === methods of manager.rb ===
    ## create_executable_command
    ## allocate_node(node_type, address, id=nil, parallel=nil)
    ## allocate_paramValueSets(request_number, src_id) # <- override
    ##
    ## update_started_parameter_state(parameter_id, executor_id)
    ## update_node_state(node_id, queueing, executing)
    ## upload_result(msg)
    ## update # <- override
    ##
    ## decrease_keepalive(node)
    ## finalize
    ##
    ## get_cluster_json
    ## get_parameter_progress
    ## get_results
    ## ===========================

    ##------------------------------------------------------------
    # override method
    #=== Allocate requested number of parameters.
    def allocate_paramValueSets(request_number, src_id)
      paramValueSetList = []   # allocated parameter value sets
      if (timeval = @database_connector.read_time(:parameter)).nil?
        return []
      end

      # get the parameter with 'ready' state.
      if (p_ready = @database_connector.read_record(
          :parameter, "state = '#{PARAMETER_STATE_READY}'")).length > 0
        p_ready.each do |p|
          break if request_number <= 0
          if (matches = @paramValueSet_pool.select { |pp|
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
              paramValueSetList.push(matches[0])
              request_number -= 1
            end
            next
          end
        end
      end

      # generate the parameter value sets from the scheduler
      @mutexAllocateParameter.synchronize{
        while request_number > 0
          newId = getNewParameterId
          if (paramValueSet = @paramDefSet.get_next(newId)).nil?
            debug("end of parameter allocation: #{@scheduler.eop}")
            break
          end

          condition = [:and] ;
          paramValueSet.paramValues.map { |p|
            condition.push([:eq, [:field, p.name], p.value]) ;
          }

          if(0 ==
             (count = @database_connector.read_count(:parameter, condition)))
            arg_hash = {parameter_id: paramValueSet.uid,
                        allocated_node_id: src_id,
                        executing_node_id: src_id,
                        allocation_start: iso_time_format(timeval),
                        execution_start: nil,
                        state: PARAMETER_STATE_ALLOCATING}
            paramValueSet.paramValues.each { |p|
              arg_hash[(p.name).to_sym] = p.value
            }
            if @database_connector.insert_record(:parameter, arg_hash).length != 0
              error("fail to insert a new parameter.")
            else
              paramValueSet.state = PARAMETER_STATE_ALLOCATING
              paramValueSetList.push(paramValueSet)
              @paramValueSet_pool.push(paramValueSet)
              request_number -= 1
            end
          else
            warn("the parameter already executed on previous or by the others." +
                 " count: #{count}" +
                 " condition: (#{condition})")
            @total_parameters -= 1
            @database_connector.read_record(:parameter, condition){|retval|
              retval.each{ |r|
                warn("result of read_record under (#{condition}): #{r}")
                paramValueSet.state = r["state"]
                @paramValueSet_pool.push(paramValueSet)
              }
            }
            debug("paramValueSet.state = #{paramValueSet.state.inspect}");
            next
          end
        end
      }
      return paramValueSetList
    end

    ##------------------------------------------------------------
    # override method
    # update is called in main loop
    def update
      cluster_tree.root.children.each do |child|
        decrease_keepalive(child)
      end
      ready_n, allocating_n, executing_n, @finished_parameters, current_finished = @database_connector.update_parameter_state(@parameter_execution_expired_timeout)
      current_finished.each do |finished_id|
        @paramValueSet_pool.each do |p|
          if p.uid == finished_id
            @paramValueSet_pool.delete(p)
            break
          end
        end
      end

      @mutexAllocateParameter.synchronize{
        @scheduler.do_variance_analysis if !@scheduler.eop
      }

      debug(cluster_tree.to_s)
      info("not allocated parameters: #{@paramDefSet.get_available}, " +
           "paramValueSet pool: #{@paramValueSet_pool.length}, " + 
           "ready: #{ready_n}, " +
           "allocating: #{allocating_n}, " +
           "executing: #{executing_n}, " +
           "finish: #{@finished_parameters}, " +
           "total: #{@total_parameters}")
      unless @message_handler.alive?
        warn("message_handler not alive")
        @message_handler.join
      end

      if @paramDefSet.get_available <= 0 and @paramValueSet_pool.length <= 0
        if @scheduler.eop # 2013/08/01
          if (retval = allocate_paramValueSets(1, 1)).length == 0
            retval.each {|r| debug("#{r}")} 
            info("call finalize !")
            finalize
          else
            error("all parameter is finished? Huh???")
          end
        end
      end
    end
    
    # 
    def generate_result_list(area, priority=0)
      result_list = { :area => area, :id => {}, :results => {}, :weight => {}, 
                      :priority => priority} #, :lerp => false}
      result_list[:area].each{|a|
        result_list[:id][a] = []
        result_list[:results][a] = []
      }
      @assign_list.each{|k,v|
        result_list[:weight] = {} if v==true
      }
      return result_list
    end

    # 
    def upload_f_test(msg)
      debug("call upload_f_test")
      id = msg[:f_test_id].to_i
      if (retval = 
          @database_connector.read_record(:f_test, 
                                          [:eq, [:field, "f_test_id"],
                                           id])).length != 0
        error("the f-test result already exist. #{retval}")
        return -1
      end
      debug("upload_f_test")
      debug("#{pp msg}")

      # msg.each{|f,v| arg_hash[f.to_sym] = v }
      if (retval = @database_connector.insert_record(
          :f_test, msg).length != 0)
        error("fail to insert new f-test result. #{retval}")
        return -2
      end
      return 0
    end

    ##------------------------------------------------------------
     
    private

    #
    def value_to_indexes(v, total_indexes, total_num)
      indexes = []
      k = v
      divider = total_num
      total_indexes.each do |i|
        divider = (divider / i).to_i
        l = (k / divider).to_i
        k -= l * divider
        indexes.push(l)
      end
      return indexes
    end

    #
    def cast_to_type(type, var)
      case type
        when "Integer" then 
          return var.to_i
        when "String" then
          return var.to_s
        when "LongString" then
          return var.to_s
        when "Float" then
          return var.to_f
        when "Double" then
          return var.to_f
        else nil
      end
    end

    #
    def getNewFtestId()
      maxid = @database_connector.read_max(:f_test, 'f_test_id', :integer) ;
      maxid ||= 0 ;
      info("maxId: #{maxid}");
      return maxid + 1 ;
    end

  end
end
