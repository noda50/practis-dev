require 'practis'
require 'doe/f_test'
require 'pp'

#
module DOEParameterGenerator
  include Practis
  include Math

  @fstep = 0.1
  @istep = 1

  #
  def self.set_step_size(definitions)
    @fstep = definitions.key?("fstep") ? definitions["fstep"] : 0.1
    @istep = definitions.key?("istep") ? definitions["istep"] : 1
  end
  
  # search only "Inside" significant parameter
  def self.generate_inside(sql_connector, orthogonal_rows, parameters, name, definition)
    param = []
    orthogonal_rows.map { |row| parameters[name][:correspond][row[name]] }
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
    new_array = []
    new_var = { :case => "inside", 
                :param => {:name => name, :paramDefs => [] }}
    var_diff = cast_decimal((param_max - param_min).abs / 3.0)
    return new_var,[] if var_diff < definition["step_size"]

    if param_min.class == Fixnum
      new_array = [param_min + var_diff.to_i, param_max - var_diff.to_i]
    elsif param_min.class == Float
      new_array = [ (param_min + var_diff).round(definition["num_decimal"]), 
                    (param_max - var_diff).round(definition["num_decimal"]) ]
    end

    # check already generated parameter (update new array)
    parameters[name][:paramDefs].sort!
    if 2 < parameters[name][:paramDefs].size
      if !parameters[name][:paramDefs].find{ |v| param_min < v && v < param_max }.nil?
        min_bit, max_bit = nil, nil
        if parameters[name][:paramDefs].include?(new_array[0]) && parameters[name][:paramDefs].include?(new_array[1])
          min_bit = parameters[name][:correspond].key(new_array.min)
          max_bit = parameters[name][:correspond].key(new_array.max)
        else
          btwn_params = []
          parameters[name][:paramDefs].each{|v| btwn_params.push(v) if param_min < v && v < param_max}
          btwn_params.sort!
          step = btwn_params.size>2 ? btwn_params.size/3 : 1
          minp = btwn_params[step - 1]
          maxp = btwn_params[btwn_params.size - step]

          if new_array.min <= minp && maxp <= new_array.max
            min_bit = parameters[name][:correspond].key(minp)
            max_bit = parameters[name][:correspond].key(maxp)
          else
          #   min_bit = parameters[name][:correspond].key(new_array.min)
          #   max_bit = parameters[name][:correspond].key(new_array.max)
          end
        end

        if !min_bit.nil? && !max_bit.nil?
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

          if (exist_area = sql_connector.read_record(:orthogonal, condition)).length > 0
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

            new_area.push(new_area_a.uniq)
            new_area.push(new_area_b.uniq)
          end
        end
      end
    end
    new_array.compact!
    new_var[:param][:paramDefs] = new_array    

    return new_var, new_area
  end

  # 
  def self.generate_outside(sql_connector, orthogonal_rows, parameters, name, definition)
    p_lmts = {:name=>name, :top=>false, :bottom=>false}
    orthogonal_rows.each{|r|
      if parameters[name][:correspond][r[name]] <= definition["bottom"]
        p_lmts[:bottom] = true
      elsif parameters[name][:correspond][r[name]] >= definition["top"]
        p_lmts[:top] = true
      end
    }
    new_var, new_area = {}, []
    
    # if !p_lmts[:bottom] && !p_lmts[:top]
    #   #both side
    #   new_var, new_area = bothside(sql_connector, orthogonal_rows, parameters, name, definition)
    # elsif !p_lmts[:top]
    #   #outside(+)
    #   new_var, new_area = generate_outside_plus(sql_connector, orthogonal_rows, parameters, name, definition)
    # elsif !p_lmts[:bottom]
    #   #outside(-)
    #   new_var, new_area = generate_outside_minus(sql_connector, orthogonal_rows, parameters, name, definition)
    # end

    #both side
    if !p_lmts[:bottom] && !p_lmts[:top]
      new_var, new_area = bothside(sql_connector, orthogonal_rows, parameters, name, definition)
    else
      new_var[:param] = {:paramDefs => [] }
    end
    return new_var, new_area
  end
  
  # search only "Out side" parameter
  def self.generate_outside_all(sql_connector, orthogonal_rows, parameters, definitions)
    new_var_list, new_area_list = [], []

    p_lmts = parameters.map{|k,v| 
      {:name=>k, :top=>false, :bottom=>false}
    }
    orthogonal_rows.each{|r|
      p_lmts.each{|prm|
        if parameters[prm[:name]][:paramDefs].min <= definitions[prm[:name]]["bottom"]
          prm[:bottom] = true
        elsif parameters[prm[:name]][:correspond][r[prm[:name]]] >= definitions[prm[:name]]["top"]
          prm[:top] = true
        end
      }
    }

    p_lmts.each{|prm|
      p "bottom: #{prm[:bottom]}, top: #{prm[:top]}"
      new_var, new_area = [], []
      if !prm[:bottom] && !prm[:top]
        #both side
        new_var, new_area = generate_bothside(sql_connector, orthogonal_rows, parameters, prm[:name], definitions[prm[:name]])
      elsif !prm[:top]
        #outside(+)
        new_var, new_area = generate_outside_plus(sql_connector, orthogonal_rows, parameters, prm[:name], definitions[prm[:name]])
      elsif !prm[:bottom]
        #outside(-)
        new_var, new_area = generate_outside_minus(sql_connector, orthogonal_rows, parameters, prm[:name], definitions[prm[:name]])
      end
      new_var_list.push(new_var) if !new_var.empty?
      new_area_list.push(new_area) if !new_area.empty?
    }

    return new_var_list, new_area_list #debug
  end

  # 
  def self.generate_wide(sql_connector, parameters, definitions, prng)
    # new_area = []
    # new_array = []
    # select min or max from each axis
    edge = {}
    parameters.each{|name, prm|
      edge[name] = []
      if prng.rand < 0.5
        edge[name].push(parameters[name][:correspond].key(prm[:paramDefs].min))
        edge[name].push(parameters[name][:correspond].key(prm[:paramDefs].sort[1]))
      else
        edge[name].push(parameters[name][:correspond].key(prm[:paramDefs].max))
        edge[name].push(parameters[name][:correspond].key(prm[:paramDefs].sort_by{|v| -v }[1]))
      end
    }
    condition = [:and]
    edge.each{ |k, v|
      condition.push([:or, [:eq, [:field, k], v[0]], [:eq, [:field, k], v[1]]])
    }
    ret = sql_connector.read_record(:orthogonal, condition)
    
    # new_area.push(ret.map{|r| r["id"]})

    return ret.map{|r| r["id"]}
  end


  private

  # not consider other parameters
  def self.bothside(sql_connector, orthogonal_rows, parameters, name, definition)
    param = []
    orthogonal_rows.each{|row|
      if !param.include?(parameters[name][:correspond][row[name]])
        param.push(parameters[name][:correspond][row[name]])
      end
    }

    # min = param.min
    # max = param.max
    exist_area = []
    new_area = []
    new_array = []

    new_upper, new_lower = nil,nil
    if param.min.class == Fixnum
      if parameters[name][:paramDefs].any?{|v| v <= param.min}
        new_lower = parameters[name][:paramDefs].select{|v| v < param.min}.max
      elsif definition["bottom"] > (param.min - @istep).to_i
        new_lower = definition["bottom"]
      else
        new_lower = (param.min - @istep).to_i
      end

      if parameters[name][:paramDefs].any?{|v| param.max < v}
        new_upper = parameters[name][:paramDefs].select{|v| param.max < v }.min
      elsif definition["top"] < (param.max + @istep).to_i
        new_upper = definition["top"]
      else
        new_upper = (param.max + @istep).to_i
      end
    elsif param.min.class == Float
      if parameters[name][:paramDefs].any?{|v| v < param.min}
        new_lower = parameters[name][:paramDefs].select{|v| v < param.min}.max
      elsif definition["bottom"] > (param.min - @fstep).round(definition["num_decimal"])
        new_lower = definition["bottom"]
      else
        new_lower = (param.min - @fstep).round(definition["num_decimal"])
      end
      if parameters[name][:paramDefs].any?{|v| param.max < v}
        new_upper = parameters[name][:paramDefs].select{|v| param.max < v }.min
      elsif definition["top"] < (param.max + @fstep).round(definition["num_decimal"])
        new_upper = definition["top"]
      else
        new_upper = (param.max + @fstep).round(definition["num_decimal"])
      end
    end

    p new_array = [new_lower, new_upper]
    pp parameters[name][:paramDefs]
    parameters[name][:paramDefs].sort!
    if 2 < parameters[name][:paramDefs].size
      if parameters[name][:paramDefs].include?(new_array.min) ||
        !(tmp = near_value(new_array.min, parameters[name][:paramDefs], name, definition)).nil?
        min_bit = parameters[name][:correspond].key(new_array.min)
        new_array.delete(new_array.min)
      end
      if parameters[name][:paramDefs].include?(new_array.max) ||
        !(tmp = near_value(new_array.max, parameters[name][:paramDefs], name, definition)).nil?
        max_bit = parameters[name][:correspond].key(new_array.max)
        new_array.delete(new_array.max)
      end
      
      if !min_bit.nil?
        pmin_bit = parameters[name][:correspond].key(param.min)
        condition = [:or]
        orCond = [:or, [:eq, [:field, name], min_bit], [:eq, [:field, name], pmin_bit]]
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
        exist_area = sql_connector.read_record(:orthogonal, condition) # nil check is easier maybe
        new_area.push(exist_area.map{|r| r["id"]})
      end

      if !max_bit.nil?
        pmax_bit = parameters[name][:correspond].key(param.max)
        condition = [:or]
        orCond = [:or, [:eq, [:field, name], max_bit], [:eq, [:field, name], pmax_bit]]
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
        exist_area = sql_connector.read_record(:orthogonal, condition) # nil check is easier maybe
        new_area.push(exist_area.map{|r| r["id"]})
      end
    end
    new_array.compact!
    new_var ={:case => "both side", 
              :param => {:name => name, :paramDefs => new_array}}
    return new_var, new_area
  end

  # search only "Both Side" parameter (consider other parameter's max,min)
  def self.generate_bothside(sql_connector, orthogonal_rows, parameters, name, definition)
    param = []
    orthogonal_rows.each{|row|
      if !param.include?(parameters[name][:correspond][row[name]])
        param.push(parameters[name][:correspond][row[name]])
      end
    }

    min = nil
    max = nil
    exist_area = []
    new_area = []
    new_array = nil

    if parameters[name][:paramDefs].min <= param.min && param.max <= parameters[name][:paramDefs].max
      min = parameters[name][:paramDefs].min
      max = parameters[name][:paramDefs].max
    else
      if param.min < parameters[name][:paramDefs].min
      error("param.min: #{param.min}")
      # TODO:
      min = param.min
      end
      if parameters[name][:paramDefs].max < param.max
      error("param.max: #{param.max}")
      # TODO:
      max = param.max
      end
    end

    # === hard coding ====

    new_upper, new_lower = nil,nil
    if param.min.class == Fixnum
      if definition["bottom"] > (min - @istep).to_i
        new_lower = definition["bottom"]
        ## @limit_var[para_name][:touch_low] = true
      else
        new_lower = (min - @istep).to_i
      end
      if definition["top"] < (max + @istep).to_i
        new_upper = definition["top"] 
        ## @limit_var[para_name][:touch_high] = true
      else
        new_upper = (max + @istep).to_i
      end
    elsif param.min.class == Float
      if definition["bottom"] > (min - @fstep).round(definition["num_decimal"])
        new_lower = definition["bottom"]
        ## @limit_var[para_name][:touch_low] = true
      else
        new_lower = (min - @fstep).round(definition["num_decimal"])
      end
      if definition["top"] < (max + @fstep).round(definition["num_decimal"])
        new_upper = definition["top"]
        # @limit_var[para_name][:touch_high] = true
      else
        new_upper = (max + @fstep).round(definition["num_decimal"])
      end
    end

    # === (end) hard coding ====


    new_array = [new_lower, new_upper]

    parameters[name][:paramDefs].sort!
    if 2 < parameters[name][:paramDefs].size
      if !parameters[name][:paramDefs].find{|v| v < param.min || param.max < v }.nil?
        if parameters[name][:paramDefs].include?(new_array[0]) && parameters[name][:paramDefs].include?(new_array[1])
          min_bit = parameters[name][:correspond].key(new_array.min)
          max_bit = parameters[name][:correspond].key(new_array.max)
        else
          #
          min = parameters[name][:paramDefs].min_by{|v| v < param.min ? v : parameters[name][:paramDefs].max}
          max = parameters[name][:paramDefs].max_by{|v| v > param.max ? v : parameters[name][:paramDefs].min}
          # min = parameters[name][:paramDefs].select{|v| v < param.min }.max
          # max = parameters[name][:paramDefs].select{|v| v > param.max }.min
          min_bit = parameters[name][:correspond].key(min)
          max_bit = parameters[name][:correspond].key(max)
          #
          # lower_arr, upper_arr = [], []
          # parameters[name][:paramDefs].each{|v|
          #   lower_arr.push(v) if v < param.min && new_array.min <= v
          #   upper_arr.push(v) if param.min < v && new_array.max <= v
          # }
          # imin = parameters[name][:paramDefs].index(lower_arr.min)
          # imax = parameters[name][:paramDefs].index(upper_arr.max)
          # if (imax - imin) % 2 == 0
          #   min_bit = parameters[name][:correspond].key(lower_arr.min)
          #   max_bit = parameters[name][:correspond].key(upper_arr.max)
          # else
          #   error("index is wrong")
          #   error("#{imax}, #{imax}: #{parameters[name]}")
          # end
        end

        if !min_bit.nil? && !max_bit.nil?
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

          exist_area = sql_connector.read_record(:orthogonal, condition) # nil check is easier maybe
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
    end

    new_var ={:case => "both side", 
              :param => {:name => name, :paramDefs => new_array}}
    return new_var, new_area
  end

  # search only "Outside(+)" significant parameter (consider other parameter's max,min)
  def self.generate_outside_plus(sql_connector, orthogonal_rows, parameters, name, definition)
    param = []
    orthogonal_rows.each{|row|
      if !param.include?(parameters[name][:correspond][row[name]])
        param.push(parameters[name][:correspond][row[name]])
      end
    }
    # p "outside(+)"
    max = parameters[name][:paramDefs].max
    exist_area = []
    new_area = []
    new_array = nil

    # var_diff = cast_decimal((param.max - param.min).abs / 3.0)

    if max.class == Fixnum
      if (max + 2*@istep) > definition["top"]
        dif = ((definition["top"] - max).abs / 2).to_i
        # return [],[] if dif <= definition["step_size"]
        if dif >= definition["step_size"]
          new_array = [max + dif, max + 2*dif] 
        end
      else
        # new_array = [max + var_diff.to_i, max + (2*var_diff).to_i]
        new_array = [max + @istep, max + 2*@istep]
      end
    elsif max.class == Float
      if (max + 2*@fstep) > definition["top"]
        dif = ((definition["top"] - max).abs / 2.0).round(definition["num_decimal"])
        if dif >= definition["step_size"]# return [],[] if dif <= definition["step_size"]
          new_array = [ (max + dif).round(definition["num_decimal"]),
                        (max + 2*dif).round(definition["num_decimal"])]
        end
      else
        # new_array = [ (max + var_diff).round(definition["num_decimal"]), 
        #               (max + 2*var_diff).round(definition["num_decimal"]) ]
        new_array = [ (max + @fstep).round(definition["num_decimal"]),
                      (max + 2*@fstep).round(definition["num_decimal"]) ]
      end
    end

    p "new array: #{new_array}"
    # var.name
    new_var ={:case => "outside(+)", 
              :param => {:name => name, :paramDefs => new_array}}
    return new_var,new_area
  end

  # search only "Outside(-)" significant parameter (consider other parameter's max,min)
  def self.generate_outside_minus(sql_connector, orthogonal_rows, parameters, name, definition)
    param = []
    orthogonal_rows.each{|row|
      if !param.include?(parameters[name][:correspond][row[name]])
        param.push(parameters[name][:correspond][row[name]])
      end
    }
    # p "outside(-)"
    min = parameters[name][:paramDefs].min # min = param.min
    exist_area = []
    new_area = []
    new_array = nil

    # var_diff = cast_decimal((param.max - param.min).abs / 3.0)

    if param.min.class == Fixnum
      if (min - @istep*2) < definition["bottom"]
        dif = ((definition["bottom"] - min).abs / 2).to_i
        # return [],[] if dif < definition["step_size"]
        if dif >= definition["step_size"]
          new_array = [min - 2*dif, min - dif] 
        end
      else
        # new_array = [param.min - var_diff.to_i, param.min - (2*var_diff).to_i]
        new_array = [param.min - 2*@istep, param.min - @istep]
      end
    elsif param.min.class == Float
      if (min - @fstep*2) < definition["bottom"]
        dif = ((definition["bottom"] - min).abs / 2.0).round(definition["num_decimal"])
        if dif >= definition["step_size"]
          new_array = [ (min - 2*dif).round(definition["num_decimal"]), 
                        (min - dif).round(definition["num_decimal"])]
        end
      else
        # new_array = [ (param.min-var_diff).round(definition["num_decimal"]),
        #               (param.min-2*var_diff).round(definition["num_decimal"]) ]
        new_array = [ (param.min - 2*@fstep).round(definition["num_decimal"]), 
                      (param.min - @fstep).round(definition["num_decimal"])]
      end
    end

    p "new array: #{new_array}"
    # var.name
    new_var ={:case => "outside(-)", 
              :param => {:name => name, :paramDefs => new_array}}
    return new_var,new_area
  end  

  #
  def self.cast_decimal(var)
    if !var.kind_of?(Float)
      return var
    else
      return BigDecimal(var.to_s)
    end
  end

  #
  def self.near_value(value, paramDefs, name, definition)
    ret = nil
    paramDefs.each{|v|
      if ((value - definition["step_size"]) < v) && (v < (value + definition["step_size"]))
        ret = v
      end
    }
    return ret
  end

end