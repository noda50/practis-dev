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

  class TestManager < Practis::Manager
    include Regression
    include OrthogonalTable

    attr_reader :va_queue
    attr_reader :current_var_set

    def initialize(config_file, parameter_file, database_file, result_file, doe_ini, myaddr = nil)
      @assign_list = {}
      @limit_var = {}
      CSV.foreach(doe_ini) do |r|
        if r[1] == "is_assigned"
          @assign_list[r[0]] = true
          @limit_var[r[0]] = {:lim_low => r[2].to_f, :lim_high => r[3].to_f, :touch_low => false, :touch_high => false}
        elsif r[1] == "is_unassigned"
          @assign_list[r[0]] = false
        end
      end
      super(config_file, parameter_file, database_file, result_file, myaddr, @assign_list)


      otable = generation_orthogonal_table(@paramDefSet.paramDefs)
      @paramDefSet = Practis::ParamDefSet.new(@paramDefSet.paramDefs, "DOEScheduler")
      @scheduler = @paramDefSet.scheduler.scheduler
      @scheduler.init_doe(@database_connector, otable, @assign_list)
      
      @total_parameters = @paramDefSet.get_total

      @mutexAnalysis = Mutex.new
      # @result_list_queue = []
      # @result_list_queue.push(generate_result_list([0,1,2,3]))
      @alloc_counter = 0
      @to_be_varriance_analysis = true
      @f_disttable = F_DistributionTable.new(0.01)      
      
      # new_var ={:case => "inside", 
      #           :param => {:name => "Noise", :paramDefs => [0.01, 0.02]}}
      # @scheduler.extend_otableDB([0,1,2,3], new_var[:case], new_var[:param])
      
      # condition = [:or, [:eq, [:field, "result_id"], 1],
      #                   [:eq, [:field, "result_id"], 2],
      #                   [:eq, [:field, "result_id"], 3]]
      # pp @database_connector.inner_join_record({base_type: :result, ref_type: :parameter,
      #                                           base_field: :result_id, ref_field: :parameter_id, 
      #                                           condition: condition})
      # exit(0)
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
        return nil
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
            if !@to_be_varriance_analysis
              info("all parameter is already allocated!")
              break
            else
              info("wait to finish analyzing result !")
              debug("id_queue flag: #{@to_be_varriance_analysis}")
              # debug("execution queue length: #{@result_list_queue.size}")
              #[2013/09/20]
              ## [2013/11/28] >>

              # if @alloc_counter < (@result_list_queue.size - 1)
              #   @alloc_counter += 1
              #   @paramDefSet.scheduler.scheduler.update_analysis(@result_list_queue[@alloc_counter][:area])
              # end
              
              ## << [2013/11/28]
              # ========
              break
            end
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
              # [2013/09/20]
                # area_index = @paramDefSet.scheduler.scheduler.get_v_index
                # if !@result_list_queue[@alloc_counter][:id][@result_list_queue[@alloc_counter][:area][area_index]].include?(newId)
                #   @result_list_queue[@alloc_counter][:id][@result_list_queue[@alloc_counter][:area][area_index]].push(newId)
                # end
              # ======
            end
          else
            warn("the parameter already executed on previous or by the others." +
                 " count: #{count}" +
                 " condition: (#{condition})")
            @total_parameters -= 1
            @database_connector.read_record(:parameter, condition){|retval|
              retval.each{ |r|
                warn("result of read_record under (#{condition}): #{r}")
                # already_id = @paramDefSet.scheduler.scheduler.already_allocation(r["parameter_id"], newId)
                paramValueSet.state = r["state"]
                @paramValueSet_pool.push(paramValueSet)
                # [2013/09/20]
                  # area_index = @paramDefSet.scheduler.scheduler.get_v_index
                  # @result_list_queue[@alloc_counter][:id][@result_list_queue[@alloc_counter][:area][area_index]].push(r["parameter_id"])
                # ============
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

      debug("id_queue flag: #{@to_be_varriance_analysis}")

      if @paramDefSet.get_available <= 0 && @to_be_varriance_analysis
        @mutexAnalysis.synchronize{variance_analysis}        
      end

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
        if !@to_be_varriance_analysis # 2013/08/01
          if (retval = allocate_paramValueSets(1, 1)).length == 0
            retval.each {|r| debug("#{r}")} 
            debug("call finalize !")
            finalize
            # @doe_file.close
          else
            error("all parameter is finished? Huh???")
          end
        end
      end
      # @doe_file.flush
    end
    
    # 
    def generate_result_list(area, priority=0)
      result_list = { :area => area, :id => {}, :results => {}, :weight => {}, 
                      :priority => priority} #, :lerp => false}
      # oa = @paramDefSet.scheduler.scheduler.oa
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
    

    # TODO: 
    private
    def check_duplicate_parameters
    end

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

    #
    def show_param_combination
      for j in 0...@paramCombinationArray[0].size
        for i in 0...@paramCombinationArray.size
          print @paramCombinationArray[i][j].to_s + ","
        end
        puts
      end
    end
  end
end
