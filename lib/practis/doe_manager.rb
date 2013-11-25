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
require 'doe/variance_analysis'
require 'doe/f_distribution_table'
require 'doe/regression'

module Practis

  class DoeManager < Practis::Manager
    include Regression

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
      @paramDefSet = Practis::ParamDefSet.new(@paramDefSet.paramDefs, "DesginOfExperimentScheduler")
      @paramDefSet.scheduler.scheduler.init_doe(@assign_list)
      @total_parameters = @paramDefSet.get_total     
      
      # [2013/09/13 H-Matsushima]
      @mutexAnalysis = Mutex.new
      @result_list_queue = []
      @result_list_queue.push(generate_result_list(@paramDefSet.scheduler.scheduler.oa.analysis_area[0]))
      @alloc_counter = 0
      @to_be_varriance_analysis = true
      @f_disttable = F_DistributionTable.new(0.01)



      msgs = init_orthogonal2db(@paramDefSet.scheduler.scheduler.oa)
      upload_orthogonal_table_db(msgs)

      # new_var ={:case => "inside", 
      #           :param => {:name => "Noise", :paramDefs => [0.01, 0.02]}}
      # @paramDefSet.scheduler.scheduler.oa.extend_table([0,1,2,3,4,5,6,7], new_var[:case], new_var[:param])
      
      # update_msgs = cast_msg4orthogonalDB([0,1,2,3,4,5,6,7], @paramDefSet.scheduler.scheduler.oa)
      # update_orthogonal_table_db(update_msgs)
      # msgs = cast_msg4orthogonalDB([8,9,10,11,12,13,14,15], @paramDefSet.scheduler.scheduler.oa)
      # upload_orthogonal_table_db(msgs)
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
      var_vec = {}
      reg_target = []
      tmp_phi = {}
      @assign_list.each{|k,v| if v then var_vec[k] = []; tmp_phi[k] = nil end }
      @result_list_queue[0][:area].each{|a|
        condition = [:or]
        @result_list_queue[0][:id][a].each{|id| 
          condition.push([:eq, [:field, "result_id"], "#{id}"]) 
        }
        retval = @database_connector.inner_join_record(
                { base_type: :result, ref_type: :parameter,
                  base_field: :result_id, ref_field: :parameter_id, 
                  condition: condition})
        if retval.length > 0
          uploaded_result_count += retval.length
          retval.each{ |r| 
            @result_list_queue[0][:results][a].push(r["value"])
            reg_target.push(r["value"])
            var_vec.each_key{ |k|
              debug("test , { #{k} => #{r[k]} }")
              var_vec[k].push(r[k])
            }
          }
        else
          debug("retval: #{retval}")
        end
      }
      debug("variance analysis =====================================")
      debug("alloc_counter: #{@alloc_counter}, queue size: #{@result_list_queue.size}")
      debug("result list:")
      debug("#{pp @result_list_queue[0]}")#result_list

      debug("uploaded_result_count: #{uploaded_result_count}, current_total: #{@paramDefSet.scheduler.scheduler.current_total}")

      if uploaded_result_count >= @paramDefSet.scheduler.scheduler.current_total
        debug("result length: #{@result_list_queue[0][:results].size}")
        debug("result: #{@result_list_queue[0]}")

        debug(" === for regress ===")
        reg_target = Vector.elements(reg_target)
        debug("#{pp var_vec}")
        debug("#{pp reg_target}")
        var_vec.each{|k,v|
          tmp_phi[k] = Matrix.rows(v.map{|e| phi(e,1)}, true)
          @result_list_queue[0][:weight][k] = (tmp_phi[k].t*tmp_phi[k]).inverse*(tmp_phi[k].t*reg_target)
        }
        debug(" === end for regress ===")

        va = VarianceAnalysis.new(@result_list_queue[0],
                                  @paramDefSet.scheduler.scheduler.oa.table,
                                  @paramDefSet.scheduler.scheduler.oa.colums)        
        upload_msg = {}
        upload_msg[:f_test_id] = getNewFtestId();
        upload_msg[:id_combination] = @result_list_queue[0][:id].values.flatten!.to_s

        debug("variance factor")
        debug("#{pp va}")
        debug("end variance analysis =====================================")
        
        if va.e_f >= 1
          significances = []
          new_param_list = []
          priority = 0.0
          va.effect_Factor.each{|ef|
            field = {}
            # significant parameter is decided
            if @f_disttable.get_Fvalue(ef[:free], va.e_f, ef[:f_value])
              significances.push(ef[:name])
              priority += ef[:f_value]
            end
            upload_msg[("range_#{ef[:name]}").to_sym] = var_vec[ef[:name]].uniq.to_s
            if ef[:f_value].nan?
              upload_msg[("f_value_of_#{ef[:name]}").to_sym] = 0.0
            else
              upload_msg[("f_value_of_#{ef[:name]}").to_sym] = ef[:f_value]
            end
            upload_msg[("gradient_of_#{ef[:name]}").to_sym] = @result_list_queue[0][:weight][ef[:name]][1]
          }

          error("error upload f-test results") if upload_f_test(upload_msg) < 0

          if 0 < significances.size
            @paramDefSet.scheduler.scheduler.oa.colums.each{|oc|
              if significances.include?(oc.parameter_name) # && 
                var = []
                @result_list_queue[0][:area].each{|r|
                  var.push(@paramDefSet.scheduler.scheduler.oa.get_parameter(r, oc.id))
                }
                tmp_var,tmp_area = generate_new_inside_parameter(var.uniq!, oc.parameter_name, @result_list_queue[0][:area])#result_list[:area])
                
                if tmp_area.empty? and !tmp_var[:param][:paramDefs].nil?
                  new_param_list.push(tmp_var)
                elsif !tmp_area.empty?
                  # ignored area is added for analysis to next_area_list
                  debug("== exist area ==")
                  debug("#{pp tmp_area}")
                  tmp_area.each{|a_list|
                    @result_list_queue.push(generate_result_list(a_list, va.get_f_value(oc.parameter_name)))
                  }
                end
              end
            }

            priority /= significances.size
            if 0 < new_param_list.size
              # generate new_param_list & extend orthogonal array
              next_area_list = generate_next_search_area( @result_list_queue[0][:area],
                                                          @paramDefSet.scheduler.scheduler.oa,
                                                          new_param_list)
              debug("next area list: ")
              debug("#{pp next_area_list}")
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

          # ===== (begin) both side =======
          bothside_flag = true
          @paramDefSet.scheduler.scheduler.oa.colums.each{|oc|
            if !var_vec[oc.parameter_name].include?(oc.parameters.max) || !var_vec[oc.parameter_name].include?(oc.parameters.min)
              bothside_flag = false
              break
            end
          }

          if bothside_flag
            @paramDefSet.scheduler.scheduler.oa.colums.each{|oc|
              var = []
              @result_list_queue[0][:area].each{|r|
                var.push(@paramDefSet.scheduler.scheduler.oa.get_parameter(r, oc.id))
              }
              if @limit_var[oc.parameter_name][:lim_low] < var.min && var.max < @limit_var[oc.parameter_name][:lim_high]
                tmp_var,tmp_area = generate_new_bothside_parameter(var.uniq!, oc.parameter_name, @result_list_queue[0][:area])

                if tmp_area.empty? and !tmp_var[:param][:paramDefs].nil?
                  new_param_list.push(tmp_var)
                elsif !tmp_area.empty?
                  # ignored area is added for analysis to next_area_list
                  debug("== exist area ==")
                  debug("#{pp tmp_area}")
                  tmp_area.each{|a_list|
                    @result_list_queue.push(generate_result_list(a_list, va.get_f_value(oc.parameter_name)))
                  }
                end
              end
            }
            priority = 1.0 #TODO: 
            if 0 < new_param_list.size
              # generate new_param_list & extend orthogonal array
              next_area_list = generate_next_search_area(@result_list_queue[0][:area],
                                                          @paramDefSet.scheduler.scheduler.oa,
                                                          new_param_list)
              debug("next area list: #{next_area_list}")
              debug("next area list:")
              debug("#{pp next_area_list}")
              next_area_list.each{|a_list|
                @result_list_queue.push(generate_result_list(a_list, priority))
              }
              if @alloc_counter < @result_list_queue.size-2
                tmp_queue = @result_list_queue.slice!(@alloc_counter+1...@result_list_queue.size)
                tmp_queue.sort_by!{|v| -v[:priority]}
                @result_list_queue += tmp_queue
              end
            end
            # ===== (end) both_side =======
          else
            p "not both side search!"
            @paramDefSet.scheduler.scheduler.oa.colums.each{|oc|
              var = []
              @result_list_queue[0][:area].each{|r|
                var.push(@paramDefSet.scheduler.scheduler.oa.get_parameter(r, oc.id))
              }
              if @limit_var[oc.parameter_name][:touch_low] && !@limit_var[oc.parameter_name][:touch_high]
                p "generate outside(+) parameter of #{oc.parameter_name}"
                tmp_var,tmp_area = generate_new_outsidep_parameter(var.uniq!, oc.parameter_name, @result_list_queue[0][:area])
                if tmp_area.empty? and !tmp_var[:param][:paramDefs].nil?
                  new_param_list.push(tmp_var)
                elsif !tmp_area.empty?
                  # ignored area is added for analysis to next_area_list
                  debug("== exist area ==")
                  debug("#{pp tmp_area}")
                  tmp_area.each{|a_list|
                    @result_list_queue.push(generate_result_list(a_list, va.get_f_value(oc.parameter_name)))
                  }
                end
              elsif @limit_var[oc.parameter_name][:touch_high] && !@limit_var[oc.parameter_name][:touch_low]
                p "generate outside(-) parameter of #{oc.parameter_name}"
                tmp_var,tmp_area = generate_new_outsidem_parameter(var.uniq!, oc.parameter_name, @result_list_queue[0][:area])
                if tmp_area.empty? and !tmp_var[:param][:paramDefs].nil?
                  new_param_list.push(tmp_var)
                elsif !tmp_area.empty?
                  # ignored area is added for analysis to next_area_list
                  debug("== exist area ==")
                  debug("#{pp tmp_area}")
                  tmp_area.each{|a_list|
                    @result_list_queue.push(generate_result_list(a_list, va.get_f_value(oc.parameter_name)))
                  }
                end
              end
            }
          end
        end

        @result_list_queue.shift
        @alloc_counter -= 1
        if @result_list_queue.size <= 0
          @to_be_varriance_analysis = false
        end
        # ============================
      end
    end
    # search only "inside" significant parameter(TODO: new parameter is determined by f-value)
    def generate_new_inside_parameter(var, para_name, area)
      debug("generate new parameter =====================================")
      debug("var: #{var}")
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

          debug("divided parameter! ==> new array: #{pp new_array}")
          debug("parameters: #{c.parameters}")

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
      new_var = { :case => "inside", 
                  :param => {:name => para_name, :paramDefs => new_array}}
      print " ==> "
      debug("#{pp new_var}")
      debug("#{pp new_area}")
      debug("end generate new parameter =====================================")
      return new_var,new_area
    end
    # TODO: new value of parameter is determined by f-value
    def generate_new_outsidep_parameter(var, para_name, area)
      debug("generate new outside(+) parameter =====================================")
      debug("var: #{var}")
      oa = @paramDefSet.scheduler.scheduler.oa
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
              new_array = [(var_max+0.004).round(5), (var_max+0.004).round(5)]
            end

            debug("generate outside(+) parameter! ==> new array: #{pp new_array}")
            debug("parameters: #{c.parameters}")
          end
          break
        end
      }

      # var.name
      new_var ={:case => "outside(+)", 
                :param => {:name => para_name, :paramDefs => new_array}}
      debug("#{pp new_var}")
      # pp @variable_set.scheduler.scheduler.oa.get_table
      debug("end generate outside(+) parameter =====================================")
      return new_var,new_area
    end
    # TODO: new value of parameter is determined by f-value
    def generate_new_outsidem_parameter(var, para_name, area)
      debug("generate new outside(-) parameter =====================================")
      debug("var: #{var}")
      oa = @paramDefSet.scheduler.scheduler.oa
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
              new_array = [(var_min-0.004).round(5), (var_min-0.004).round(5)]
            end

            debug("generate outside(-) parameter! ==> new array: #{pp new_array}")
            debug("parameters: #{c.parameters}")
          end
          break
        end
      }

      # var.name
      new_var ={:case => "outside(-)", 
                :param => {:name => para_name, :paramDefs => new_array}}
      debug("#{pp new_var}")
      # pp @variable_set.scheduler.scheduler.oa.get_table
      debug("end generate outside(-) parameter =====================================")
      return new_var,new_area
    end
    # TODO: new value of parameter is determined by f-value
    def generate_new_bothside_parameter(var, para_name, area)
      debug("generate new both side parameter =====================================")
      debug("var: #{var}")
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
          if c.parameters.min <= var_min && var_max <= c.parameters.max
            min=c.parameters.min
            max=c.parameters.max
          else
            if var_min < c.parameters.min
            error("var_min: #{var_min}")
            # TODO:
            min = var_min
            end
            if c.parameters.max < var_max
            error("var_max: #{var_max}")
            # TODO:
            max = var_max
            end
          end
          var_diff = cast_decimal((max - min).abs / 2.0)
          new_upper,new_lower = nil,nil
          if var_min.class == Fixnum
            # new_upper,new_lower = (min-var_diff).to_i, (max+var_diff).to_i
            if @limit_var[para_name][:lim_low] > (min-2).to_i
              new_lower = @limit_var[para_name][:lim_low]
              @limit_var[para_name][:touch_low] = true
            else
              new_lower = (min-2).to_i
            end
            if @limit_var[para_name][:lim_high] < (max+2).to_i
              new_upper = @limit_var[para_name][:lim_high]
              @limit_var[para_name][:touch_high] = true
            else
              new_upper = (max+2).to_i
            end
          elsif var_min.class == Float
            # new_upper,new_lower =(min-var_diff).round(5), (max+var_diff).round(5)
            if @limit_var[para_name][:lim_low] > (min-0.004).round(5)
              new_lower = @limit_var[para_name][:lim_low]
              @limit_var[para_name][:touch_low] = true
            else
              new_lower = (min-0.004).round(5)
            end
            if @limit_var[para_name][:lim_high] < (max+0.004).round(5)
              new_upper = @limit_var[para_name][:lim_high]
              @limit_var[para_name][:touch_high] = true
            else
              new_upper = (max+0.004).round(5)
            end
          end
          new_array = [new_lower,new_upper]
          debug("generate both side parameter! ==> new array: #{pp new_array}")
          debug("parameters: #{c.parameters}")

          if 2 < c.parameters.size
            if c.parameters.find{|v| v<var_min && var_max<v }.nil?
              break
            else
              if c.parameters.include?(new_array[0]) && c.parameters.include?(new_array[1])
                min_bit = c.get_bit_string(new_array.min)
                max_bit = c.get_bit_string(new_array.max)
              else
                # min = c.parameters.min_by{|v| v > var_min ? v : c.parameters.max}
                # max = c.parameters.max_by{|v| v < var_max ? v : c.parameters.min}
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
                elsif tmp_bit[tmp_bit.size - 1] == "1"
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

          # break
        end
      }
      # var.name
      new_var ={:case => "both side", 
                :param => {:name => para_name, :paramDefs => new_array}}
      debug("#{pp new_var}")
      debug("end generate both side parameter =====================================")
      puts
      return new_var,new_area
    end

    # return array of new searching parameters (area) 
    def generate_next_search_area(area, oa, new_param_list)
      new_area = []
      new_inside_area = []
      new_outside_area = []
      debug("generate next search =====================================")
      debug("old area: #{area} --> ")
      debug("new_param_list:")
      debug("#{pp new_param_list}")

      inside_list = []
      outside_list = []
      new_param_list.each{ |np| 
        if np[:case] == "inside" 
          inside_list.push(np)
        else
          outside_list.push(np)
        end
      }

      if !inside_list.empty?
        extclm = oa.extend_table(area, inside_list[0][:case], inside_list[0][:param])
        extend_otableDB(area, inside_list[0][:case], inside_list[0][:param])
        exit(0)


        new_inside_area += oa.generate_new_analysis_area(area, inside_list[0], extclm)
        debug("#{pp new_inside_area}")
        if 2 <= inside_list.size
          for i in 1...inside_list.size
            extclm = oa.extend_table(area, inside_list[i][:case], inside_list[i][:param])
            tmp_area = []
            new_inside_area.each { |na|
              tmp_area += oa.generate_new_analysis_area(na, inside_list[i], extclm)
            }
            new_inside_area = tmp_area
          end
        end
        debug("inside new area: #{new_inside_area}")
        debug("inside new area")
        debug("#{pp new_inside_area}")
      end

      if !outside_list.empty?
        extclm = oa.extend_table(area, outside_list[0][:case], outside_list[0][:param])
        extend_otableDB(area, outside_list[0][:case], outside_list[0][:param])
        exit(0)

        new_outside_area += oa.generate_new_analysis_area(area, outside_list[0], extclm)
        debug("#{pp new_outside_area}")
        if 2 <= outside_list.size
          for i in 1...outside_list.size
            extclm = oa.extend_table(area, outside_list[i][:case], outside_list[i][:param])
            tmp_area = []
            new_outside_area.each { |na|
              tmp_area += oa.generate_new_analysis_area(na, outside_list[i], extclm)
            }
            new_outside_area += tmp_area
            new_outside_area += oa.generate_new_analysis_area(area, outside_list[i], extclm)
          end
        end
        debug("outside new area: #{new_outside_area}")
        debug("outside new area")
        debug("#{pp new_outside_area}")
      end

      new_area = new_inside_area + new_outside_area

      debug("#{new_area}")
      debug("#{pp new_area}")
      debug("end generate next search =====================================")
      return new_area
    end
    # 
    def generate_result_list(area, priority=0)
      result_list = { :area => area, :id => {}, :results => {}, :weight => {}, 
                      :priority => priority, :lerp => false}
      oa = @paramDefSet.scheduler.scheduler.oa
      result_list[:area].each{|a|
        result_list[:id][a] = []
        result_list[:results][a] = []
      }
      @assign_list.each{|k,v|
        if v then result_list[:weight] = {} end
      }
      
      oa.colums.each{|col|
        has_max,has_min = false,false
        result_list[:area].each{|a|
          if col.parameters.max == oa.get_parameter(a, col.id)
            has_max = true
          elsif col.parameters.min == oa.get_parameter(a, col.id)
            has_min = true
          end
        }
        if has_min && has_max then result_list[:lerp] = true end
      }
      return result_list
    end

    # upload additional tables
    def upload_orthogonal_table_db(msgs=nil)
      return -2 if msgs.nil?
      
      msgs.each{|msg|
        id = msg[:id].to_i
        if (retval =  
            @database_connector.read_record(:orthogonal, [:eq, [:field, "id"], id])).length == 0
          if (retval = @database_connector.insert_record(
            :orthogonal, msg).length != 0)
            error("fail to insert new orthogonal table. #{retval}")
            return -2
          end
        end  
      }
      
      return 0
    end
    # update exisiting table
    def update_orthogonal_table_db(msgs=nil)
      msgs.each{|msg|
        id = msg[:id].to_i
        
        if (retval = 
            @database_connector.read_record(:orthogonal, [:eq, [:field, "id"], id])).length != 0
          # update
          flag = false
          upld = {}
          retval.each{|ret|
            ret.each{|k, v|    
              if msg[k.to_sym] != v
                upld[k.to_sym] = msg[k.to_sym]
                flag = true
              end
            }
          }
          if flag
            nret = @database_connector.update_record(:orthogonal, upld, [:eq, [:field, "id"], id])
            debug("#{pp nret}")
          end          
        end
      }
    end
    #
    def extend_otableDB(area, add_point_case, parameter)
      old_level = 0
      old_digit_num = 0
      twice = false
      ext_column = nil

      condition = [:or, [:field, "id"]] + area
      retval = @database_connector.read_record(:orthogonal, condition)
      if retval.length == 0
        error("the no orthogonal array exist.")
        return -1
      end

      oldlevel = @database_connector.read_distinct_record(:orthogonal, "#{parameter[:name]}" ).length
      old_digit_num = retval[0][parameter[:name]].size#oldlevel / 2
      

      if old_digit_num < (sqrt(oldlevel+parameter[:paramDefs].size).ceil)

        twice = true
        upload_msgs = []
        update_msgs = []
        retval.each{|ret|
          upload_msgs.push("1" + ret[parameter[:name]])
          h = {id: ret["id"]}
          ret.each{|k,v|
            k == parameter[:name] ? h[k.to_sym] = "0" + v : h[k.to_sym] = v
          }
          update_msgs.push(h)
        }
        update_orthogonal_table_db(update_msgs)
      end

      if twice
        # upload_orthogonal_table_db(msg)
      end

      exit(0)

      @colums.each{ |oc|
        if oc.parameter_name == parameter[:name]
          ext_column = oc
          old_level = oc.level        
          oc.update_level(parameter[:paramDefs].size)
          old_digit_num = oc.digit_num
          if oc.equal_digit_num(old_digit_num)
            oc.padding(old_digit_num, old_level)
            twice = true
            copy = []
            for i in 0...@table[oc.id].size
              copy.push("1" + @table[oc.id][i])
              @table[oc.id][i] = "0" + @table[oc.id][i]
            end
            @table[oc.id] += copy
            @l_size *= 2
          end
          oc.assign_parameter(old_level, add_point_case, parameter[:paramDefs])
          break
        end
      }
      if twice
        @table.each_with_index{|c, i|
          extend_flag = true
          @colums.each{|oc| 
            if oc.id == i && oc.parameter_name == parameter[:name]
              extend_flag = false
              break
            end 
          }
          if extend_flag
            copy = []
            @table[i].each{ |b| copy.push(b) }
            @table[i] += copy
          end
        }
      end
      return ext_column
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

    private
    def init_orthogonal2db(oa)
      msgs = []
      oa.l_size.times {|row|
        msg = {:id => row, :run => 0}
        oa.colums.each{|col|
          msg["#{col.parameter_name}".to_sym] = oa.get_bit_string(col.id,row)
        }
        msgs.push(msg)
      }
      return msgs
    end

    def cast_msg4orthogonalDB(area, oa)
      msgs = []
      area.each{|a|
        msg = {:id => a, :run => 0}
        oa.colums.each{|col|
          msg["#{col.parameter_name}".to_sym] = oa.get_bit_string(col.id, a)
        }
        msgs.push(msg)
      }
      return msgs
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
