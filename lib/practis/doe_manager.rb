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

    def initialize(config_file, parameter_file, database_file, result_file, doe_ini, myaddr = nil)
      super(config_file, parameter_file, database_file, result_file, myaddr)
      @paramDefSet = Practis::ParamDefSet.new(@paramDefSet.paramDefs, "DesginOfExperimentScheduler")
      @paramDefSet.scheduler.scheduler.init_doe(doe_ini)
      @total_parameters = @paramDefSet.get_total
      
      # [2013/09/13 H-Matsushima]
      @mutexAnalysis = Mutex.new
      @result_list_queue = []
      @result_list_queue.push(generate_result_list(@paramDefSet.scheduler.scheduler.oa.analysis_area[0]))
      @alloc_counter = 0
      @to_be_varriance_analysis = true
      @f_disttable = F_DistributionTable.new(0.01)
      # @doe_file = open("doe.log", "w")
    end

    # === methods of manager.rb ===
    # create_executable_command
    # allocate_node(node_type, address, id=nil, parallel=nil)
    # allocate_paramValueSets(request_number, src_id) # <- override

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
              debug("execution queue length: #{@result_list_queue.size}")
              #[2013/09/20]
              if @alloc_counter < (@result_list_queue.size - 1)
                @alloc_counter += 1
                @paramDefSet.scheduler.scheduler.update_analysis(@result_list_queue[@alloc_counter][:area])
              end
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
              area_index = @paramDefSet.scheduler.scheduler.get_v_index
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
                already_id = @paramDefSet.scheduler.scheduler.already_allocation(r["parameter_id"], newId)
                paramValueSet.state = r["state"]
                @paramValueSet_pool.push(paramValueSet)
                # [2013/09/20]
                area_index = @paramDefSet.scheduler.scheduler.get_v_index
                @result_list_queue[@alloc_counter][:id][@result_list_queue[@alloc_counter][:area][area_index]].push(r["parameter_id"])
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
            }
          else
            debug("retval: #{retval}")
          end
        }
      }
      p "variance analysis ====================================="
      p "alloc_counter: #{@alloc_counter}, queue size: #{@result_list_queue.size}"
      p "result list:"
      pp @result_list_queue[0]#result_list

      if uploaded_result_count >= @paramDefSet.scheduler.scheduler.current_total
        debug("result length: #{@result_list_queue[0][:results].size}")
        debug("result: #{@result_list_queue[0]}")        
        
        va = VarianceAnalysis.new(@result_list_queue[0],
                                  @paramDefSet.scheduler.scheduler.oa.table,
                                  @paramDefSet.scheduler.scheduler.oa.colums)
        p "variance factor"
        pp va
        
        if va.e_f >= 1
          num_significance = []
          new_param_list = []
          priority = 0.0
          va.effect_Factor.each{|ef|
            # significant parameter is decided
            if @f_disttable.get_Fvalue(ef[:free], va.e_f, ef[:f_value])
              num_significance.push(ef[:name])
              priority += ef[:f_value]
            end
          }
          if 0 < num_significance.size
            @paramDefSet.scheduler.scheduler.oa.colums.each{|oc|
              if num_significance.include?(oc.parameter_name)
                var = []
                @result_list_queue[0][:area].each{|r|
                  var.push(@paramDefSet.scheduler.scheduler.oa.get_parameter(r, oc.id))
                }
                tmp_var,tmp_area = generate_new_inside_parameter(var.uniq!, oc.parameter_name, @result_list_queue[0][:area])#result_list[:area])
                # tmp_var,tmp_area = generate_new_outsidem_parameter(var.uniq!, oc.parameter_name, @result_list_queue[0][:area])
                # tmp_var,tmp_area = generate_new_outsidep_parameter(var.uniq!, oc.parameter_name, @result_list_queue[0][:area])

                if tmp_area.empty? and !tmp_var[:param][:paramDefs].nil?
                  new_param_list.push(tmp_var)
                elsif !tmp_area.empty?
                  # ignored area is added for analysis to next_area_list
                  p "== exist area =="
                  pp tmp_area
                  tmp_area.each{|a_list|
                    @result_list_queue.push(generate_result_list(a_list, va.get_f_value(oc.parameter_name)))
                  }
                end
              end
            }
            priority /= num_significance.size
            if 0 < new_param_list.size
              # generate new_param_list & extend orthogonal array
              next_area_list = generate_next_search_area(@result_list_queue[0][:area],
                                                          @paramDefSet.scheduler.scheduler.oa,
                                                          new_param_list)
              debug("next area list: ")
              pp next_area_list
              next_area_list.each{|a_list|
                @result_list_queue.push(generate_result_list(a_list, priority))
              }
              if @alloc_counter < @result_list_queue.size-2
                tmp_queue = @result_list_queue.slice!(@alloc_counter+1...@result_list_queue.size)
                tmp_queue.sort_by!{|v| -v[:priority]}
                @result_list_queue += tmp_queue
              end
            end
          end
        end

        @result_list_queue.shift
        @alloc_counter -= 1
        if @result_list_queue.size <= 0
          @to_be_varriance_analysis = false
        end
      end
      p "end variance analysis ====================================="
      puts
    end
    # search only "inside" significant parameter(TODO: new parameter is determined by f-value)
    def generate_new_inside_parameter(var, para_name, area)
      p "generate new parameter ====================================="
      p "var: #{var}"
      oa = @paramDefSet.scheduler.scheduler.oa
      var_min = var.min
      var_max = var.max
      min=nil
      max=nil
      exist_area = []
      new_area = []
      new_array = nil
      oa.colums.each{|c|
        if para_name == c.parameter_name
          var_diff = cast_decimal((var_max - var_min).abs / 3.0)
          if var_min.class == Fixnum
            new_array = [var_min+var_diff.to_i, var_max-var_diff.to_i]
          elsif var_min.class == Float
            new_array = [(var_min+var_diff).round(5), (var_max-var_diff).round(5)]
          end

          p "divided parameter! ==> new array: #{pp new_array}"
          p "parameters: #{c.parameters}"

          if 2 < c.parameters.size
            if c.parameters.find{|v| var_min<v && v<var_max}.nil?
              break
            else
              if c.parameters.include?(new_array[0]) && c.parameters.include?(new_array[1])
                min_bit = c.get_bit_string(new_array.min)
                max_bit = c.get_bit_string(new_array.max)
              else
                min = c.parameters.min_by{|v| v > var_min ? v : c.parameters.max}
                max = c.parameters.max_by{|v| v < var_max ? v : c.parameters.min}
                min_bit = c.get_bit_string(min)
                max_bit = c.get_bit_string(max)
              end

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
              new_area_a = []
              new_area_b = []
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
              break
            end
          end
        end
      }

      # var.name
      new_var ={:case => "inside", 
                :param => {:name => para_name, :paramDefs => new_array}}
      print " ==> "
      pp new_var
      p "end generate new parameter ====================================="
      puts
      return new_var,new_area
    end
    # TODO: new parameter is determined by f-value
    def generate_new_outsidep_parameter(var, para_name, area)
      p "generate new outside(+) parameter ====================================="
      p "var: #{var}"
      oa = @variable_set.scheduler.scheduler.oa
      var_min = var.min
      var_max = var.max
      min=nil
      max=nil

      new_area = []
      new_array = nil

      oa.colums.each{|c|
        if para_name == c.parameter_name
          if c.parameters.max <= var_max
            min=c.parameters.min
            max=c.parameters.max
            var_diff = cast_decimal((var_max - var_min).abs / 3.0)

            if var_min.class == Fixnum
              # new_array = [var_max+var_diff.to_i, var_max+(2*var_diff).to_i]
              new_array = [var_max+2, var_max+4]
            elsif var_min.class == Float
              # new_array = [(var_max+var_diff).round(5), (var_max+2*var_diff).round(5)]
              new_array = [(var_max+0.0025).round(5), (var_max+0.005).round(5)]
            end

            p "generate outside(+) parameter! ==> new array: #{pp new_array}"
            p "parameters: #{c.parameters}"
          end
          break
        end
      }

      # var.name
      new_var ={:case => "outside(+)", 
                :param => {:name => para_name, :variables => new_array}}
      print " ==> "
      pp new_var
      # pp @variable_set.scheduler.scheduler.oa.get_table
      p "end generate outside(+) parameter ====================================="
      puts
      return new_var,new_area
    end
    # TODO: new parameter is determined by f-value
    def generate_new_outsidem_parameter(var, para_name, area)
      p "generate new outside(-) parameter ====================================="
      p "var: #{var}"
      oa = @variable_set.scheduler.scheduler.oa
      var_min = var.min
      var_max = var.max
      min=nil
      max=nil

      new_area = []
      new_array = nil

      oa.colums.each{|c|
        if para_name == c.parameter_name
          if var_min <= c.parameters.min
            min=c.parameters.min
            max=c.parameters.max
            var_diff = cast_decimal((var_max - var_min).abs / 3.0)

            if var_min.class == Fixnum
              # new_array = [var_min-var_diff.to_i, var_min-(2*var_diff).to_i]
              new_array = [var_min-4, var_min-2]
            elsif var_min.class == Float
              # new_array = [(var_min-var_diff).round(5), (var_min-2*var_diff).round(5)]
              new_array = [(var_min-0.005).round(5), (var_min-0.0025).round(5)]
            end

            p "generate outside(-) parameter! ==> new array: #{pp new_array}"
            p "parameters: #{c.parameters}"
          end
          break
        end
      }

      # var.name
      new_var ={:case => "outside(-)", 
                :param => {:name => para_name, :variables => new_array}}
      print " ==> "
      pp new_var
      # pp @variable_set.scheduler.scheduler.oa.get_table
      p "end generate outside(-) parameter ====================================="
      puts
      return new_var,new_area
    end

    # return array of new searching parameters (area) 
    def generate_next_search_area(area, oa, new_param_list)
      new_area = []
      p "generate next search ====================================="
      p "old area: #{area} --> "
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
    def generate_result_list(area, priority=0)
      result_list = { :area => area, :id => {}, :results => {}, :priority => priority }
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

    # TODO: 
    private
    def check_duplicate_parameters
      
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
