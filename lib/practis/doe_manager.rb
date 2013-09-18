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
      # @va_queue = []
      @variable_set = Practis::VariableSet.new(@variable_set.variable_set, "DesginOfExperimentScheduler")
      @total_parameters = @variable_set.get_total
      
      # hash = {:size => @variable_set.get_total, :list => {}}
      # :list[] = {:are => , :result => []} 
      # @id_list_queue = []
      # @id_list_queue.push(hash)
      
      # [2013/09/13 H-Matsushima]
      @area_list = []
      @area_list.push(@variable_set.scheduler.scheduler.analysis[:area])

      # @va_counter = 0
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
              break
            end
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
            end
          else
            warn("the parameter already executed on previous or by the others." +
                 " count: #{count}" +
                 " condition: (#{condition})")
            @total_parameters -= 1
            @database_connector.read_record(:parameter, condition){|retval|
              retval.each{ |r|
                warn("result of read_record under (#{condition}): #{r}")
                @variable_set.scheduler.scheduler.already_allocation(r["parameter_id"], newId)
                parameter.state = r["state"]
                @parameter_pool.push(parameter)
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

      # :TODO
      if @variable_set.get_available <= 0
        variance_analysis
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
      result_list = { :area => @variable_set.scheduler.scheduler.analysis[:area],
                      :results => {} }
      tmp_flag = false
      @variable_set.scheduler.scheduler.analysis[:result_id].each{|area, ids|
        if !result_list[:results].key?(area)
          result_list[:results][area] = []
        end
        ids.each{|v|
          if (retval = @database_connector.read_record(:result, "result_id = '#{v}'")).length > 0
            uploaded_result_count += 1
            retval.each{ |r| result_list[:results][area].push(r["value"]) }
          else
            debug("retval: #{retval}")
            p "nothing?: #{v}"
            tmp_flag = true
          end
        }
        if tmp_flag then 
          pp @variable_set.scheduler.scheduler.analysis 
          pp @variable_set.scheduler.scheduler.oa
        end
      }
      pp @variable_set.scheduler.scheduler.analysis[:result_id]

      if uploaded_result_count >= @area_list[0].size
        debug("result length: #{result_list.size}")
        debug("result: #{result_list}")
        pp @variable_set.scheduler.scheduler.oa.colums
        result_list[:area].each{|a| pp @variable_set.scheduler.scheduler.oa.get_parameter_set(a)}
        pp result_list
        p "================================================"
        va = VarianceAnalysis.new(result_list,
                                  @variable_set.scheduler.scheduler.oa.table,
                                  @variable_set.scheduler.scheduler.oa.colums)
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
            @variable_set.variable_set.each { |v|
              if num_significance.include?(v.name)
                new_param_list.push(generate_new_parameter(v))
              end
            }
            # generate new_param_list & extend orthogonal array
            next_area_list = generate_next_search_area(@variable_set.scheduler.scheduler.analysis[:area],
                                                          @variable_set.scheduler.scheduler.oa,
                                                          new_param_list)
            debug("next area list: ")
            pp next_area_list
            pp @variable_set.scheduler.scheduler.oa
            @area_list += next_area_list
          end
        end

        @area_list.shift
        @variable_set.scheduler.scheduler.update_analysis(@area_list[0])

        if @area_list.size <= 0 
          @to_be_varriance_analysis = false
        end
        
        # debug("#{pp @area_list}")
        # exit(0)
      end
    end

    ##------------------------------------------------------------
    # var: parameter (Practis::Variable)
    # divide_size: 
    # return array of variable_array
    def divide_parameter_range(var, divide_size = 2)
      parameters_array = []

      tmp_name = Marshal.load(Marshal.dump(var.name))
      tmp_type = Marshal.load(Marshal.dump(var.type))
      # tmp_start = BigDecimal(Marshal.load(Marshal.dump(var.parameters[0])).to_s)
      # tmp_end = BigDecimal(Marshal.load(Marshal.dump(var.parameters[var.parameters.length - 1])).to_s)
      tmp_start = cast_decimal(Marshal.load(Marshal.dump(var.parameters[0])))
      tmp_end = cast_decimal(Marshal.load(Marshal.dump(var.parameters[var.parameters.length - 1])))
      tmp_divide_size = divide_size

      # divided_range = ((tmp_end - tmp_start) / tmp_divide_size.to_f)
      divided_range = (tmp_end - tmp_start) / BigDecimal(tmp_divide_size.to_s)

      # tmp_start = cast_to_type(tmp_type.to_s, tmp_start)
      # tmp_end = cast_to_type(tmp_type.to_s, tmp_end)
      # divided_range = cast_to_type(tmp_type.to_s, divided_range)

      if divided_range != 0
        divide_size.times{|i|
          if i == 0
            tmp_pattern = "[{\"type\":\"include_range\",\"start\":" + 
                            tmp_start.to_s + ",\"end\":" + 
                            # (tmp_start + (i + 1) * divided_range).to_s + 
                            # ",\"step\":"+ divided_range.to_s + "}]"
                            cast_to_type(tmp_type.to_s, tmp_start + (i + 1) * divided_range).to_s +                             
                            ",\"step\":"+ cast_to_type(tmp_type.to_s, divided_range).to_s + "}]"
          elsif (i + 1) == divide_size
            tmp_pattern = "[{\"type\":\"include_range\",\"start\":" + 
                            # (tmp_start + i * divided_range).to_s + ",\"end\":" + 
                            # tmp_end.to_s + ",\"step\":"+ divided_range.to_s + "}]"
                            cast_to_type(tmp_type.to_s, (tmp_start + i * divided_range)).to_s + 
                            ",\"end\":" + cast_to_type(tmp_type.to_s, tmp_end).to_s + 
                            ",\"step\":"+ cast_to_type(tmp_type.to_s, divided_range).to_s + "}]"
          else
            tmp_pattern = "[{\"type\":\"include_range\",\"start\":" + 
                            # (tmp_start + i * divided_range).to_s + ",\"end\":" + (tmp_start + (i + 1) * divided_range).to_s + 
                            # ",\"step\":"+ divided_range.to_s + "}]"
                            cast_to_type(tmp_type.to_s, tmp_start + i * divided_range).to_s + 
                            ",\"end\":" + cast_to_type(tmp_type.to_s, tmp_start + (i + 1) * divided_range).to_s + 
                            ",\"step\":"+ cast_to_type(tmp_type.to_s, divided_range).to_s + "}]"
          end
          debug("#{tmp_pattern}")
          parameters_array.push(Practis::Variable.new(tmp_name, tmp_type.to_s, tmp_pattern))
        }

        return parameters_array
      else
        return nil
      end
    end

    # search only "inside" significant parameter
    def generate_new_parameter(var)
      oa = @variable_set.scheduler.scheduler.oa
      var_min = var.parameters.min
      var_max = var.parameters.max
      min=nil
      max=nil
      oa.colums.each{|c|
        if var.name == c.parameter_name
          if 2 < c.parameters.size
            min = c.parameters.min_by{|v| v > var_min ? v : 0}
            max = c.parameters.max_by{|v| v < var_max ? v : 0}
          else
            min = var_min
            max = var_max
          end
          break
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
                :param => {:name => var.name, :variables => new_array}}
      return new_var
    end

    # return array of new searching parameters (area) 
    def generate_next_search_area(area, oa, new_param_list)
      new_area = []

      debug("new param list: #{new_param_list}")
      debug("area: #{area}")
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
      return new_area
    end

    ##------------------------------------------------------------
    def cast_decimal(var)
      if !var.kind_of?(Float)
        return var
      else
        return BigDecimal(var.to_s)
      end
    end

    ##------------------------------------------------------------
    # override method
    #
    def get_parameter_progress
      finished = nil
      if (retval = @database_connector.read_record(
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

    private
    def check_uploaded_result_count
      if @area_list.size <= 0 
        @to_be_varriance_analysis = false
        return false
      end



      # if @id_list_queue.length <= 0
      #   @to_be_varriance_analysis = false;
      #   return false
      # end
      
      # uploaded_result_count = 0
      # result_list = []
      # @id_list_queue[0][:list].each{|lk, lv|
      #   tmp = []
      #   lv.each{ |v|
      #     if (retval = @database_connector.read_record(:result, "result_id = '#{v}'")).length > 0
      #       uploaded_result_count += 1
      #       retval.each{ |r| tmp.push(r["value"]) }
      #     else
      #       debug("retval: #{retval}")
      #     end
      #   }
      #   result_list.push(tmp)
      # }
      # debug("list queue size: #{@id_list_queue.length}")
      # debug("id list: #{@id_list_queue[0][:list]}")# debug("id list: #{@id_list}")
      # debug("result length: #{result_list.size}")
      # debug("result: #{result_list}")

      # if uploaded_result_count >= @id_list_queue[0][:size]
      #   return true
      # else
      #   return false
      # end
    end

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