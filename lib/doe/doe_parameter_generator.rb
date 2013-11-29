require 'doe/f_test'
require 'pp'

#
module DOEParameterGenerator
  include Math

  
  # search only "Inside" significant parameter
  def generate_inside(orthogonal_rows, parameter, name)
    created = []

    pp orthogonal_rows
    pp parameter

    param_min = parameter[name][:paramDefs].min
    param_max = parameter[name][:paramDefs].max
    min=nil
    max=nil
    exist_area = []
    new_area = []
    new_array = nil

    var_diff = cast_decimal((param_max - param_min).abs / 3.0)
    if param_min.class == Fixnum
      new_array = [param_min + var_diff.to_i, param_max - var_diff.to_i]
    elsif param_min.class == Float
      new_array = [(param_min + var_diff).round(5), (param_max - var_diff).round(6)]
    end

    if 2 < parameter[name][:paramDefs].size
      if parameter[name][:paramDefs].find{|v| var_min<v && v<var_max}.nil?
      else
        if parameter[name][:paramDefs].include?(new_array[0])&&parameter[name][:paramDefs].include?(new_array[1])
          min_bit = parameter[name][:correspond].key(new_array.min)
          max_bit = parameter[name][:correspond].key(new_array.max)
        else
          min = parameter[name][:paramDefs].min_by{|v| v > var_min ? v : parameter[name][:paramDefs].max}
          max = parameter[name][:paramDefs].max_by{|v| v < var_max ? v : parameter[name][:paramDefs].min}
          min_bit = parameter[name][:correspond].key(min)
          max_bit = parameter[name][:correspond].key(max)
        end
      end
    end

    ### check exist area
    #parameter[name][:correspond].has
    # oa.table[c.id].each_with_index{|b, i|
    #   if  b == min_bit || b == max_bit
    #     area.each{|row|
    #       flag = true
    #       oa.table.each_with_index{|o, j|
    #         if j != c.id
    #           if o[i] != o[row]
    #             flag = false
    #             break
    #           end
    #         end
    #       }
    #       if flag then exist_area.push(i) end
    #     }
    #   end
    # }
    # new_area.push(exist_area)

    # new_area_a = []
    # new_area_b = []

    # exist_area.each{|row|
    #   tmp_bit = oa.get_bit_string(c.id, row)
    #   if tmp_bit[tmp_bit.size - 1] == "0"
    #     new_area_a.push(row)
    #   elsif tmp_bit[tmp_bit.size-1] == "1"
    #     new_area_b.push(row)
    #   end
    # }

    # orthogonal_rows.each{|row|
    #   tmp_bit = row[name]
    #   if tmp_bit[tmp_bit.size - 1] == "0"
    #     new_area_b.push(row["id"])
    #   elsif tmp_bit[tmp_bit.size - 1] == "1"
    #     new_area_a.push(row["id"])
    #   end
    # }
    # new_area.push(new_area_a)
    # new_area.push(new_area_b)
    
    ###

    new_var = { :case => "inside", 
                :param => {:name => name, :paramDefs => new_array}}

    return new_var, new_area
  end

  # search only "Both Side" significant parameter
  def generate_bothside(orthogonal_rows, parameter, name)
    
  end

  # search only "Outside(+)" significant parameter
  def generate_outside_plus(orthogonal_rows, parameter, name)
    
  end

  # search only "Outside(-)" significant parameter
  def generate_outside_minus(orthogonal_rows, parameter, name)
    
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


  private

  #
  def cast_decimal(var)
      if !var.kind_of?(Float)
        return var
      else
        return BigDecimal(var.to_s)
      end
    end

end