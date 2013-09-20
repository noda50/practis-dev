#!/usr/bin/ruby
# -*- coding: utf-8 -*-

require 'rubygems'
require 'json'
require 'bigdecimal'

# require 'thread'

require 'practis/cluster'
require 'practis/daemon'
require 'practis/database_connector'
require 'practis/message_handler'
require 'practis/net'
require 'practis/parameter_parser'
require 'practis/result_parser'


require 'doe/orthogonal_array'
require 'doe/variance_analysis'
require 'doe/f_distribution_table'

module Practis

  class DoeManager < Practis::Manager

    attr_reader :va_queue
    attr_reader :current_var_set

    def initialize(config_file, parameter_file, database_file, result_file, myaddr = nil)
      super(config_file, parameter_file, database_file, result_file, myaddr)
      
      @variable_set = Practis::VariableSet.new(@variable_set.variable_set, "DesginOfExperimentScheduler")
      @total_parameters = @variable_set.get_total
      
      # [2013/09/13 H-Matsushima]
      @mutexAnalysis = Mutex.new
      # @area_list = []
      # @area_list.push(@variable_set.scheduler.scheduler.oa.analysis_area[0])
      @result_list_queue = []
      @result_list_queue.push(generate_result_list(@variable_set.scheduler.scheduler.oa.analysis_area[0]))
      @alloc_counter = 0
      @to_be_varriance_analysis = true
      @f_disttable = F_DistributionTable.new(0.01)
      # @doe_file = open("doe.log", "w")
    end

    # === methods of manager.rb ===
    # create_executable_command
    # allocate_node(node_type, address, id=nil, parallel=nil)
    # allocate_parameters(request_number, src_id) # <- override

    # update_started_parameter_state(parameter_id, executor_id)
    # update_node_state(node_id, queueing, executing)
    # upload_result(msg)
    # update # <- override

    # decrease_keepalive(node)
    # finalize
    
    # get_cluster_json
    # get_parameter_progress
    # get_results
    # ===========================

    ##------------------------------------------------------------
    # override method
    #=== Allocate requested number of parameters.
    def allocate_parameters(request_number, src_id)
      parameters = []   # allocated parameters
      if (timeval = @database_connector.read_time(:parameter)).nil?
        return nil
      end

      # get the parameter with 'ready' state.
      if (p_ready = @database_connector.read_record(
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
      @mutexAllocateParameter.synchronize{
        while request_number > 0
          newId = getNewParameterId
          if (parameter = @variable_set.get_next(newId)).nil?
            if !@to_be_varriance_analysis
              info("all parameter is already allocated!")
              break
            else
              info("wait to finish analyzing result !")
              debug("id_queue flag: #{@to_be_varriance_analysis}")
              debug("execution queue length: #{@result_list_queue.size}")
              #[2013/09/20]
              if @alloc_counter < (@result_list_queue.size - 1)
                @alloc_counter += 1
                @variable_set.scheduler.scheduler.update_analysis(@result_list_queue[@alloc_counter][:area])
              end
              # ========
              break
            end
          # else
          #   #[2013/09/20]
          #   area_index = @variable_set.scheduler.scheduler.get_v_index
          #   debug("area_index: #{area_index}, id:#{newId}")
          #   # debug("#{@result_list_queue[@alloc_counter]}")
          #   if !@result_list_queue[@alloc_counter][:id][@result_list_queue[@alloc_counter][:area][area_index]].include?(newId)
          #     @result_list_queue[@alloc_counter][:id][@result_list_queue[@alloc_counter][:area][area_index]].push(newId)
          #   end
          #   # ======
          end

          # condition = parameter.parameter_set.map { |p|
          #   "#{p.name} = '#{p.value}'" }.join(" and ")
          # debug("#{condition}, id: #{parameter.uid}")
          condition = [:and] ;
          parameter.parameter_set.map { |p|
            condition.push([:eq, [:field, p.name], p.value]) ;
          }

          if(0 ==
             (count = @database_connector.read_count(:parameter, condition)))
            arg_hash = {parameter_id: parameter.uid,
                        allocated_node_id: src_id,
                        executing_node_id: src_id,
                        allocation_start: iso_time_format(timeval),
                        execution_start: nil,
                        state: PARAMETER_STATE_ALLOCATING}
            parameter.parameter_set.each { |p|
              arg_hash[(p.name).to_sym] = p.value
            }
            if @database_connector.insert_record(:parameter, arg_hash).length != 0
              error("fail to insert a new parameter.")
            else
              parameter.state = PARAMETER_STATE_ALLOCATING
              parameters.push(parameter)
              @parameter_pool.push(parameter)
              request_number -= 1
              # [2013/09/20]
              area_index = @variable_set.scheduler.scheduler.get_v_index
              debug("area_index: #{area_index}, id:#{newId}")
              # debug("#{@result_list_queue[@alloc_counter]}")
              if !@result_list_queue[@alloc_counter][:id][@result_list_queue[@alloc_counter][:area][area_index]].include?(newId)
                @result_list_queue[@alloc_counter][:id][@result_list_queue[@alloc_counter][:area][area_index]].push(newId)
              end
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
                already_id = @variable_set.scheduler.scheduler.already_allocation(r["parameter_id"], newId)
                parameter.state = r["state"]
                @parameter_pool.push(parameter)
                # [2013/09/20]
                area_index = @variable_set.scheduler.scheduler.get_v_index
                @result_list_queue[@alloc_counter][:id][@result_list_queue[@alloc_counter][:area][area_index]].push(r["parameter_id"])
                # ============
              }
            }
            debug("parameter.state = #{parameter.state.inspect}");
            next
          end
        end
      }
      return parameters
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
        @parameter_pool.each do |p|
          if p.uid == finished_id
            @parameter_pool.delete(p)
            break
          end
        end
      end

      debug("id_queue flag: #{@to_be_varriance_analysis}")

      if @variable_set.get_available <= 0 && @to_be_varriance_analysis
        @mutexAnalysis.synchronize{variance_analysis}        
      end

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

      if @variable_set.get_available <= 0 and @parameter_pool.length <= 0
        if !@to_be_varriance_analysis # 2013/08/01
          if (retval = allocate_parameters(1, 1)).length == 0
            retval.each {|r| debug("#{r}")}
            finalize
            # @doe_file.close
          else
            error("all parameter is finished? Huh???")
          end
        end
      end
      # @doe_file.flush
    end

    ##------------------------------------------------------------
    # variance analysis
    def variance_analysis
      uploaded_result_count = 0
      # [2013/09/20]
      @result_list_queue[0][:area].each{|a| @result_list_queue[0][:results][a].clear}
      @result_list_queue[0][:area].each{|a|
        @result_list_queue[0][:id][a].each{|id|
          if (retval = @database_connector.read_record(:result, "result_id = '#{id}'")).length > 0
            uploaded_result_count += 1
            retval.each{ |r| 
              @result_list_queue[0][:results][a].push(r["value"])
              # uploaded_result_count += 1
            }
          else
            debug("retval: #{retval}")
          end
        }
      }
      # =======
      # @variable_set.scheduler.scheduler.analysis[:result_id].each{|area, ids|
      #   if !result_list[:results].key?(area)
      #     result_list[:results][area] = []
      #   end
      #   ids.each{|v|
      #     if (retval = @database_connector.read_record(:result, "result_id = '#{v}'")).length > 0
      #       uploaded_result_count += 1
      #       retval.each{ |r| 
      #         result_list[:results][area].push(r["value"])
      #         # uploaded_result_count += 1
      #       }
      #     else
      #       debug("retval: #{retval}")
      #     end
      #   }
      # }
      # ========
      p "variance analysis ====================================="
      p "result list:"
      pp @result_list_queue[0]#result_list

      if uploaded_result_count >= @variable_set.scheduler.scheduler.current_total
        # debug("result length: #{result_list.size}")
        # debug("result: #{result_list}")
        debug("result length: #{@result_list_queue[0][:results].size}")
        debug("result: #{@result_list_queue[0]}")        
        
        va = VarianceAnalysis.new(@result_list_queue[0],
                                  @variable_set.scheduler.scheduler.oa.table,
                                  @variable_set.scheduler.scheduler.oa.colums)
        p "variance factor"
        pp va
        
        if va.e_f >= 1
          num_significance = []
          new_param_list = []
          va.effect_Factor.each{|ef|
            # significant parameter is decided
            if @f_disttable.get_Fvalue(ef[:free], va.e_f, ef[:f_value])
              num_significance.push(ef[:name])
            end            
          }
          if 0 < num_significance.size
            @variable_set.scheduler.scheduler.oa.colums.each{|oc|
              if num_significance.include?(oc.parameter_name)
                var = []
                #result_list[:area].each{|r|
                @result_list_queue[0][:area].each{|r|
                  var.push(@variable_set.scheduler.scheduler.oa.get_parameter(r, oc.id))
                }
                tmp_var,tmp_area = generate_new_parameter(var.uniq!, oc.parameter_name, @result_list_queue[0][:area])#result_list[:area])
                if tmp_area.empty?
                  new_param_list.push(tmp_var)
                else
                  # ignored area is added for analysis to next_area_list
                  tmp_area.each{|a_list|
                    @result_list_queue.push(generate_result_list(a_list))
                  }
                  # @area_list += tmp_area
                end
              end
            }

            if 0 < new_param_list.size 
              # generate new_param_list & extend orthogonal array
              next_area_list = generate_next_search_area(@result_list_queue[0][:area],#result_list[:area],
                                                          @variable_set.scheduler.scheduler.oa,
                                                          new_param_list)
              debug("next area list: ")
              pp next_area_list
              next_area_list.each{|a_list|
                @result_list_queue.push(generate_result_list(a_list))
              }
              # @area_list += next_area_list
            end
          end
        end

        @result_list_queue.shift
        @alloc_counter -= 1
        # @area_list.shift
        # if @area_list.size <= 0
        if @result_list_queue.size <= 0
          @to_be_varriance_analysis = false
        # else
        #   @variable_set.scheduler.scheduler.update_analysis(@area_list[0])  
        end
      end
      p "end variance analysis ====================================="
      puts
    end
    # search only "inside" significant parameter
    def generate_new_parameter(var, para_name, area)
      p "generate new parameter ====================================="
      pp var
      oa = @variable_set.scheduler.scheduler.oa
      var_min = var.min
      var_max = var.max
      min=nil
      max=nil
      exist_area = []
      new_area = []
      oa.colums.each{|c|
        if para_name == c.parameter_name
          if 2 < c.parameters.size
            if c.parameters.find{|v| var_min<v && v<var_max}.nil?
              min = var_min
              max = var_max
            else
              min = c.parameters.min_by{|v| v > var_min ? v : c.parameters.max}
              max = c.parameters.max_by{|v| v < var_max ? v : c.parameters.min}
              min_bit = c.get_bit_string(min)
              max_bit = c.get_bit_string(max)

              oa.table[c.id].each_with_index{|b, i|
                if  b == min_bit || b == max_bit
                  area.each{|row|
                    flag = true
                    oa.table.each_with_index{|o, j|
                      if j != c.id
                        if o[i] != o[row]
                          flag = false
                          break
                        end
                      end
                    }
                    if flag then exist_area.push(i) end
                  }
                end
              }
              new_area.push(exist_area)
              new_area_a =[]
              new_area_b =[]
              exist_area.each{|row|
                tmp_bit = oa.get_bit_string(c.id, row)
                if tmp_bit[tmp_bit.size - 1] == "0"
                  new_area_a.push(row)
                elsif tmp_bit[tmp_bit.size-1] == "1"
                  new_area_b.push(row)
                end
              }
              area.each{|row|
                tmp_bit = oa.get_bit_string(c.id, row)
                if tmp_bit[tmp_bit.size - 1] == "0"
                  new_area_b.push(row)
                elsif tmp_bit[tmp_bit.size - 1] == "1"
                  new_area_a.push(row)
                end
              }
              new_area.push(new_area_a)
              new_area.push(new_area_b)
              break # return exist_area
            end
          else
            min = var_min
            max = var_max
          end
        end
      }
      var_diff = cast_decimal((max - min).abs / 3.0)

      if min.class == Fixnum
        new_array = [min+var_diff.to_i, max-var_diff.to_i]
      elsif min.class == Float
        new_array = [(min+var_diff).round(5), (max-var_diff).round(5)]
      end

      # var.name
      new_var ={:case => "inside", 
                :param => {:name => para_name, :variables => new_array}}
      print " ==> "
      pp new_var
      pp @variable_set.scheduler.scheduler.oa.get_table
      p "end generate new parameter ====================================="
      puts
      return new_var,new_area
    end
    # return array of new searching parameters (area) 
    def generate_next_search_area(area, oa, new_param_list)
      new_area = []
      p "generate next search ====================================="
      p "new_param_list:"
      pp new_param_list
      

      extclm = oa.extend_table(area, new_param_list[0][:case], new_param_list[0][:param])
      new_area += oa.generate_new_analysis_area(area, new_param_list[0], extclm)
      
      if 2 <= new_param_list.size
        for i in 1...new_param_list.size
          extclm = oa.extend_table(area, new_param_list[i][:case], new_param_list[i][:param])
          tmp_area = []
          new_area.each { |na| 
            tmp_area += oa.generate_new_analysis_area(na, new_param_list[i], extclm)
          }
          new_area = tmp_area
        end
      end
      debug("#{new_area}")
      pp new_area
      p "end generate next search ====================================="
      puts
      return new_area
    end
    # 
    def generate_result_list(area)
      result_list = { :area => area, :id => {}, :results => {} }
      result_list[:area].each{|a|
        result_list[:id][a] = []
        result_list[:results][a] = []
      }
      return result_list
    end

    ##------------------------------------------------------------
    def cast_decimal(var)
      if !var.kind_of?(Float)
        return var
      else
        return BigDecimal(var.to_s)
      end
    end

    #
    private
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
    private
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