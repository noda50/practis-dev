require 'doe/f_test'
require 'pp'

#
module DOEParameterGenerator
  include Math

  
  # search only "Inside" significant parameter
  def generate_inside(sql_connetor, orthogonal_rows, parameters, name)
    param = []
    orthogonal_rows.each{|row|
      if !param.include?(parameters[name][:correspond][row[name]])
        param.push(parameters[name][:correspond][row[name]])
      end
    }

    param_min = param.min
    param_max = param.max
    min=nil
    max=nil
    exist_area = []
    new_area = []
    new_array = nil

    var_diff = cast_decimal((param_max - param_min).abs / 3.0)
    if param_min.class == Fixnum
      new_array = [param_min + var_diff.to_i, param_max - var_diff.to_i]
    elsif param_min.class == Float
      new_array = [(param_min + var_diff).round(6), (param_max - var_diff).round(6)]
    end

    if 2 < parameters[name][:paramDefs].size
      if parameters[name][:paramDefs].find{ |v| param_min < v && v < param_max }.nil?
      else
        if parameters[name][:paramDefs].include?(new_array[0]) && parameters[name][:paramDefs].include?(new_array[1])
          min_bit = parameters[name][:correspond].key(new_array.min)
          max_bit = parameters[name][:correspond].key(new_array.max)
        else
          min = parameters[name][:paramDefs].min_by{|v| v > param_min ? v : parameters[name][:paramDefs].max}
          max = parameters[name][:paramDefs].max_by{|v| v < param_max ? v : parameters[name][:paramDefs].min}
          min_bit = parameters[name][:correspond].key(min)
          max_bit = parameters[name][:correspond].key(max)
        end

        condition = [:or]
        orCond = [:or, [:eq, [:field, name], min_bit], [:eq, [:field, name], max_bit]]
        orthogonal_rows.each{|row|
          andCond = [:and]
          row.each{ |k, v|
            if k != "id" and k != "run" and k != name and !v.nil?
              andCond.push([:eq, [:field, k], v])
            end
          }
          andCond.push(orCond)
          condition.push(andCond)
        }

        exist_area = sql_connetor.read_record(:orthogonal, condition) # nil check is easier maybe
        
        new_area.push(exist_area.map{|r| r["id"]})
        
        new_area_a = []
        new_area_b = []

        exist_area.each{|r|
          new_area_a.push(r["id"]) if r[name][r[name].size - 1] == "0"
          new_area_b.push(r["id"]) if r[name][r[name].size - 1] == "1"
        }
        orthogonal_rows.map{|r|
          new_area_a.push(r["id"]) if r[name][r[name].size - 1] == "1"
          new_area_b.push(r["id"]) if r[name][r[name].size - 1] == "0"
        }

        new_area.push(new_area_a)
        new_area.push(new_area_b)

      end
    end
    
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
    param_min = var.min
    param_max = var.max
    min=nil
    max=nil

    new_area = []
    new_array = nil

    oa.colums.each{|c|
      if para_name == c.parameter_name
        if c.parameters.max <= param_max
          min=c.parameters.min
          max=c.parameters.max
          var_diff = cast_decimal((param_max - param_min).abs / 3.0)

          if param_min.class == Fixnum
            # new_array = [param_max+var_diff.to_i, param_max+(2*var_diff).to_i]
            new_array = [param_max+2, param_max+4]
          elsif param_min.class == Float
            # new_array = [(param_max+var_diff).round(6), (param_max+2*var_diff).round(6)]
            new_array = [(param_max+0.004).round(6), (param_max+0.004).round(6)]
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
    param_min = var.min
    param_max = var.max
    min=nil
    max=nil

    new_area = []
    new_array = nil

    oa.colums.each{|c|
      if para_name == c.parameter_name
        if param_min <= c.parameters.min
          min=c.parameters.min
          max=c.parameters.max
          var_diff = cast_decimal((param_max - param_min).abs / 3.0)

          if param_min.class == Fixnum
            # new_array = [param_min-var_diff.to_i, param_min-(2*var_diff).to_i]
            new_array = [param_min-4, param_min-2]
          elsif param_min.class == Float
            # new_array = [(param_min-var_diff).round(6), (param_min-2*var_diff).round(6)]
            new_array = [(param_min-0.004).round(6), (param_min-0.004).round(6)]
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
    param_min = var.min
    param_max = var.max
    min=nil
    max=nil
    
    exist_area = []
    new_area = []
    new_array = nil
    oa.colums.each{|c|
      if para_name == c.parameter_name
        if c.parameters.min <= param_min && param_max <= c.parameters.max
          min=c.parameters.min
          max=c.parameters.max
        else
          if param_min < c.parameters.min
          error("param_min: #{param_min}")
          # TODO:
          min = param_min
          end
          if c.parameters.max < param_max
          error("param_max: #{param_max}")
          # TODO:
          max = param_max
          end
        end
        var_diff = cast_decimal((max - min).abs / 2.0)
        new_upper,new_lower = nil,nil
        if param_min.class == Fixnum
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
        elsif param_min.class == Float
          # new_upper,new_lower =(min-var_diff).round(6), (max+var_diff).round(6)
          if @limit_var[para_name][:lim_low] > (min-0.004).round(6)
            new_lower = @limit_var[para_name][:lim_low]
            @limit_var[para_name][:touch_low] = true
          else
            new_lower = (min-0.004).round(6)
          end
          if @limit_var[para_name][:lim_high] < (max+0.004).round(6)
            new_upper = @limit_var[para_name][:lim_high]
            @limit_var[para_name][:touch_high] = true
          else
            new_upper = (max+0.004).round(6)
          end
        end
        new_array = [new_lower,new_upper]
        debug("generate both side parameter! ==> new array: #{pp new_array}")
        debug("parameters: #{c.parameters}")

        if 2 < c.parameters.size
          if c.parameters.find{|v| v<param_min && param_max<v }.nil?
            break
          else
            if c.parameters.include?(new_array[0]) && c.parameters.include?(new_array[1])
              min_bit = c.get_bit_string(new_array.min)
              max_bit = c.get_bit_string(new_array.max)
            else
              # min = c.parameters.min_by{|v| v > param_min ? v : c.parameters.max}
              # max = c.parameters.max_by{|v| v < param_max ? v : c.parameters.min}
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