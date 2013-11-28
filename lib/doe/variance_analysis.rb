require 'doe/f_test'
require 'pp'
#
class VarianceAnalysis
  
  #
  def initialize
    @f_disttable = F_DistributionTable.new(0.01)
  end


  def do_f_test(result_set, table, columns)

    va = FTest.new
    va.do_test(result_set, table, columns)

    significances = []
    if va.e_f >= 1
      new_param_list = []
      priority = 0.0
      va.effect_Factor.each{|ef|
        field = {}
        # significant parameter is decided
        if @f_disttable.get_Fvalue(ef[:free], va.e_f, ef[:f_value])
          significances.push(ef[:name])
          priority += ef[:f_value]
        end
      }
    end

    # generate inside parameters set
    if 0 < significances.size

    end







    upload_msg = {}
    upload_msg[:f_test_id] = getNewFtestId();
    upload_msg[:id_combination] = @result_list_queue[0][:id].values.flatten!.to_s


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