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
      @va_queue = []
      @current_var_set = Practis::VariableSet.new(@variable_set.variable_set, "DesginOfExperimentScheduler")
      debug("/-/-/-/-/-/-/-/-/-/-/-/-/")
      pp @current_var_set.variable_set
      exit(0)

      # @name_list = ["Noise","NumOfGameIteration"]
      @current_var_set.scheduler.prepareDoE(@name_list)
      @total_parameters = @current_var_set.get_total
      
      hash ={:list => id_list = {}, :size => @current_var_set.get_total}
      @id_list_queue = []
      @id_list_queue.push(hash)
      @va_counter = 0
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
          if (parameter = @current_var_set.get_next(newId)).nil?
            if @va_queue.length <= 0 
              if !@to_be_varriance_analysis
                info("all parameter is already allocated!")
                break
              else
                info("wait to finish analyzing result !")
                debug("exe queue size: #{@va_queue.length}")
                debug("id quequ: #{@id_list_queue}")
                debug("va counter: #{@va_counter}")
                debug("id_queue flag: #{@to_be_varriance_analysis}")
                break
              end
            else
              debug("queue length: #{@va_queue.length}")
              @current_var_set = @va_queue.shift
              @va_counter += 1
              @to_be_varriance_analysis = true

              if @current_var_set.nil?
                debug("no more parameter set !!")
                break# finalize
              end

              @total_parameters += @current_var_set.get_total

              info( "#{@current_var_set} \n" +
              "not allocated parameters: #{@current_var_set.get_available}, " +
              "finish: #{@finished_parameters}, " +
              "total: #{@total_parameters}")

              parameter = @current_var_set.get_next(newId)
            end
          end

          condition = parameter.parameter_set.map { |p|
            "#{p.name} = '#{p.value}'" }.join(" and ")
          debug("#{condition}, id: #{parameter.uid}")

          res_key = []
          debug("parameter set: #{parameter.parameter_set}")
          parameter.parameter_set.each { |p|
            if @name_list.include?(p.name)
              res_key.push("#{p.name} = '#{p.value}'")
            end
          }

          debug("\n res_key: #{res_key} \n")
          tmp_res_key = res_key.map { |p| "#{p}"}.join(" and ")

          if !@id_list_queue[@va_counter][:list].include?(tmp_res_key)
            @id_list_queue[@va_counter][:list][tmp_res_key] = []
          end


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
            @id_list_queue[@va_counter][:list][tmp_res_key].push(parameter.uid)
            if @database_connector.insert_column(:parameter, arg_hash).length != 0
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
                info(r)
                @id_list_queue[@va_counter][:list][tmp_res_key].push(r["parameter_id"])
                if(parameter.uid != r["parameter_id"])
                  parameter.state = r["state"]
                  @parameter_pool.push(parameter)
                end
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
      debug("id quequ: #{@id_list_queue}")
      debug("va counter: #{@va_counter}")

      if check_uploaded_result_count
        variance_analysis
      end

      debug(cluster_tree.to_s)
      info("not allocated parameters: #{@current_var_set.get_available}, " +
           "ready: #{ready_n}, " +
           "allocating: #{allocating_n}, " +
           "executing: #{executing_n}, " +
           "finish: #{@finished_parameters}, " +
           "total: #{@total_parameters}")
      unless @message_handler.alive?
        warn("message_handler not alive")
        @message_handler.join
      end

      debug("\n\n check the requirement for finish !! \n")

      if va_queue.length <= 0 
        if @current_var_set.get_available <= 0 and @parameter_pool.length <= 0
          debug("\n\n check available: #{@current_var_set.get_available} \n pool: #{@parameter_pool}")
          if !@to_be_varriance_analysis # 2013/08/01
            debug("\n\n check flag: #{@to_be_varriance_analysis} !! \n")
            if (retval = allocate_parameters(1, 1)).length == 0
              debug("\n\n check allocate parameter !! \n")
              retval.each {|r| debug("#{r}")}
              finalize
              # @doe_file.close
            else
              error("all parameter is finished? Huh???")
            end
          end
        end
      end
      # @doe_file.flush
    end

    ##------------------------------------------------------------
    # test variance analysis
    def variance_analysis
      uploaded_result_count = 0
      result_list = []
      @id_list_queue[0][:list].each{|lk, lv|
        tmp = []
        lv.each{ |v|
          if (retval = @database_connector.read_record(:result, "result_id = '#{v}'")).length > 0
            uploaded_result_count += 1
            retval.each{ |r| tmp.push(r["value"]) }
          else
            debug("retval: #{retval}")
          end
        }
        result_list.push(tmp)
      }

      
      if uploaded_result_count >= @id_list_queue[0][:size]
        # if uploaded_result_count > 20
          # @doe_file.write("Num. of uploaded results #{uploaded_result_count}\n")
        # end
        debug("id list: #{@id_list_queue[0][:list]}")
        debug("result length: #{result_list.size}")
        debug("result: #{result_list}")
        factor_names = []
        @current_var_set.scheduler.scheduler.get_factor_indexes.each_key{|k| factor_names.push(k)}
        va = VarianceAnalysis.new(@current_var_set.scheduler.scheduler.get_factor_indexes, result_list, factor_names, 2)
        #
        # va = VarianceAnalysis.new()
        # significant parameter is divide !!

        if va.e_f >= 1
          next_parameter_set_seed = Hash.new
          num_significance = 0
          # debug("name list: #{@name_list}")
          # @current_var_set.variable_set.each { |v| debug("variable_set: #{v}")}
          @current_var_set.variable_set.each { |v|
            # debug("variable set: #{v}")
            if @name_list.include?(v.name)
              # debug("F value: #{va.f[v.name]}, F error: #{va.e_f}")
              if @f_disttable.get_Fvalue(1, va.e_f, va.f[v.name])
                if !(div_param = divide_parameter_range(v, 2)).nil?
                  next_parameter_set_seed[v.name] = div_param
                  # debug("hash: #{next_parameter_set_seed[v.name]}")
                  # debug("length: #{next_parameter_set_seed[v.name].length}")
                  num_significance += 1
                else
                  next_parameter_set_seed[v.name] = []
                  next_parameter_set_seed[v.name].push(Marshal.load(Marshal.dump(v)))
                  # debug("hash: #{next_parameter_set_seed[v.name]}")
                  # debug("length: #{next_parameter_set_seed[v.name].length}")
                end
              else
                next_parameter_set_seed[v.name] = []
                next_parameter_set_seed[v.name].push(Marshal.load(Marshal.dump(v)))
                # debug("hash: #{next_parameter_set_seed[v.name]}")
                # debug("length: #{next_parameter_set_seed[v.name].length}")
              end
            else
              next_parameter_set_seed[v.name] = []
              next_parameter_set_seed[v.name].push(Marshal.load(Marshal.dump(v)))
              # debug("hash: #{next_parameter_set_seed[v.name]}")
              # debug("length: #{next_parameter_set_seed[v.name].length}")
            end
            
          }
          debug("number of significant parameter: #{num_significance}")
          if 0 < num_significance
            nexet_parameter_set_seed_indexes = []
            next_parameter_set_seed.each_value{|v| nexet_parameter_set_seed_indexes.push(v.length) }
            debug("nexet_parameter_set_seed_indexes: #{nexet_parameter_set_seed_indexes}")
            next_parameter_set_seed_total = 1
            nexet_parameter_set_seed_indexes.collect{|t| next_parameter_set_seed_total *= t}

            next_parameter_set_seed_total.times{ |i|
              tmp_indexes = value_to_indexes(i, nexet_parameter_set_seed_indexes, next_parameter_set_seed_total)
              debug("tmp_indexes: #{tmp_indexes}")
              variables_array = []
              index_counter = 0
              next_parameter_set_seed.each_value{ |v|
                debug("counter: #{index_counter}, ")
                variables_array.push(v[tmp_indexes[index_counter]])
                index_counter += 1
              }
              next_parameter = Practis::VariableSet.new(variables_array, "DesginOfExperimentScheduler")
              debug("next parameter set: #{next_parameter}")
              # @doe_file.write("#{next_parameter}\n")
              @va_queue.push(next_parameter)

              # TODO: modify
              # next_parameter.scheduler.prepareDoE(@name_list)

              hash ={:list => id_list = {}, :size => next_parameter.get_total}
              @id_list_queue.push(hash)
            }
          end
        end
        # @id_list = {}
        @id_list_queue.shift
        @va_counter -= 1
        if @id_list_queue.size <= 0
          @to_be_varriance_analysis = false
        end
        
        # debug("\n \t !! Results of allocated parameter are stored in DB !! \n")
      end
      # debug("queue of DoE parameter set: #{@va_queue}")
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
      total = @current_var_set.get_total
      hash[:total_parameters] = total
      hash[:finished_parameters] = @finished_parameters
      va = []
      @current_var_set.variable_set.each do |v|
        va.push({:name => v.name, :values => v.parameters})
      end
      hash[:variables] = va
      pa = []
      hash[:progress] = pa
      l = @current_var_set.variable_set.length
      (0..l - 2).each do |i|
        (i + 1..l - 1).each do |j|
          v1 = @current_var_set.variable_set[i]
          v2 = @current_var_set.variable_set[j]
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
      if @id_list_queue.length <= 0
        @to_be_varriance_analysis = false;
        return false
      end
      
      uploaded_result_count = 0
      result_list = []
      @id_list_queue[0][:list].each{|lk, lv|
        tmp = []
        lv.each{ |v|
          if (retval = @database_connector.read_record(:result, "result_id = '#{v}'")).length > 0
            uploaded_result_count += 1
            retval.each{ |r| tmp.push(r["value"]) }
          else
            debug("retval: #{retval}")
          end
        }
        result_list.push(tmp)
      }
      debug("list queue size: #{@id_list_queue.length}")
      debug("id list: #{@id_list_queue[0][:list]}")# debug("id list: #{@id_list}")
      debug("result length: #{result_list.size}")
      debug("result: #{result_list}")

      if uploaded_result_count >= @id_list_queue[0][:size]
        return true
      else
        return false
      end
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