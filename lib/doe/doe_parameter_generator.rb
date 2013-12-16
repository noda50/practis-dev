require 'practis'
require 'doe/f_test'
require 'pp'

#
module DOEParameterGenerator
  include Practis
  include Math
  
  # search only "Inside" significant parameter
  def self.generate_inside(sql_connetor, orthogonal_rows, parameters, name, definition)
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
    new_var = { :case => "inside", 
                :param => {:name => name, :paramDefs => nil}}

    var_diff = cast_decimal((param_max - param_min).abs / 3.0)
    return new_var,[] if var_diff <= definition["step_size"]

    if param_min.class == Fixnum
      new_array = [param_min + var_diff.to_i, param_max - var_diff.to_i]
    elsif param_min.class == Float
      new_array = [ (param_min + var_diff).round(definition["num_decimal"]), 
                    (param_max - var_diff).round(definition["num_decimal"]) ]
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

        if (exist_area = sql_connetor.read_record(:orthogonal, condition)).length > 0
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

    new_var[:param][:paramDefs] = new_array

    return new_var, new_area
  end

  def self.generate_outside(sql_connetor, orthogonal_rows, parameters, name, definition)
    
  end
  
  # search only "Out side" parameter
  def self.generate_outside_all(sql_connetor, orthogonal_rows, parameters, definitions)
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
        new_var, new_area = generate_bothside(sql_connetor, orthogonal_rows, parameters, prm[:name], definitions[prm[:name]])
      elsif !prm[:top]
        #outside(+)
        new_var, new_area = generate_outside_plus(sql_connetor, orthogonal_rows, parameters, prm[:name], definitions[prm[:name]])
      elsif !prm[:bottom]
        #outside(-)
        new_var, new_area = generate_outside_minus(sql_connetor, orthogonal_rows, parameters, prm[:name], definitions[prm[:name]])
      end
      new_var_list.push(new_var) if !new_var.empty?
      new_area_list.push(new_area) if !new_area.empty?
    }

    return new_var_list, new_area_list #debug
  end


  private

  # search only "Both Side" parameter
  def self.generate_bothside(sql_connetor, orthogonal_rows, parameters, name, definition)
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
    ##hard coding
    istep = 9
    fstep = 0.03
    ##hard coding

    new_upper, new_lower = nil,nil
    if param.min.class == Fixnum
      if definition["bottom"] > (min - istep).to_i
        new_lower = definition["bottom"]
        ## @limit_var[para_name][:touch_low] = true
      else
        new_lower = (min - istep).to_i
      end
      if definition["top"] < (max + istep).to_i
        new_upper = definition["top"] 
        ## @limit_var[para_name][:touch_high] = true
      else
        new_upper = (max + istep).to_i
      end
    elsif param.min.class == Float
      if definition["bottom"] > (min - fstep).round(definition["num_decimal"])
        new_lower = definition["bottom"]
        ## @limit_var[para_name][:touch_low] = true
      else
        new_lower = (min - fstep).round(definition["num_decimal"])
      end
      if definition["top"] < (max + fstep).round(definition["num_decimal"])
        new_upper = definition["top"]
        # @limit_var[para_name][:touch_high] = true
      else
        new_upper = (max + fstep).round(definition["num_decimal"])
      end
    end

    # === (end) hard coding ====


    new_array = [new_lower, new_upper]

    if 2 < parameters[name][:paramDefs].size
      if parameters[name][:paramDefs].find{|v| v < param.min && param.max < v }.nil?
      else
        if parameters[name][:paramDefs].include?(new_array[0]) && parameters[name][:paramDefs].include?(new_array[1])
          min_bit = parameters[name][:correspond].key(new_array.min) # c.get_bit_string(new_array.min)
          max_bit = parameters[name][:correspond].key(new_array.max)# c.get_bit_string(new_array.max)
        else
          min = parameters[name][:paramDefs].min_by{|v| v > param.min ? v : parameters[name][:paramDefs].max}
          max = parameters[name][:paramDefs].max_by{|v| v < param.max ? v : parameters[name][:paramDefs].min}
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

    new_var ={:case => "both side", 
              :param => {:name => name, :paramDefs => new_array}}
    return new_var, new_area
  end

  # search only "Outside(+)" significant parameter
  def self.generate_outside_plus(sql_connetor, orthogonal_rows, parameters, name, definition)
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

    ##hard coding
    istep = 9
    fstep = 0.03
    ##hard coding

    # var_diff = cast_decimal((param.max - param.min).abs / 3.0)

    if max.class == Fixnum
      if (max + 2*istep) > definition["top"]
        dif = ((definition["top"] - max).abs / 2).to_i
        # return [],[] if dif <= definition["step_size"]
        if dif >= definition["step_size"]
          new_array = [max + dif, max + 2*dif] 
        end
      else
        # new_array = [max + var_diff.to_i, max + (2*var_diff).to_i]
        new_array = [max + istep, max + 2*istep]
      end
    elsif max.class == Float
      if (max + 2*fstep) > definition["top"]
        dif = ((definition["top"] - max).abs / 2.0).round(definition["num_decimal"])
        if dif >= definition["step_size"]# return [],[] if dif <= definition["step_size"]
          new_array = [ (max + dif).round(definition["num_decimal"]),
                        (max + 2*dif).round(definition["num_decimal"])]
        end
      else
        # new_array = [ (max + var_diff).round(definition["num_decimal"]), 
        #               (max + 2*var_diff).round(definition["num_decimal"]) ]
        new_array = [ (max + fstep).round(definition["num_decimal"]),
                      (max + 2*fstep).round(definition["num_decimal"]) ]
      end
    end

    p "new array: #{new_array}"
    # var.name
    new_var ={:case => "outside(+)", 
              :param => {:name => name, :paramDefs => new_array}}
    return new_var,new_area
  end

  # search only "Outside(-)" significant parameter
  def self.generate_outside_minus(sql_connetor, orthogonal_rows, parameters, name, definition)
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

    ##hard coding
    istep = 9
    fstep = 0.03
    ##hard coding

    # var_diff = cast_decimal((param.max - param.min).abs / 3.0)

    if param.min.class == Fixnum
      if (min - istep*2) < definition["bottom"]
        dif = ((definition["bottom"] - min).abs / 2).to_i
        # return [],[] if dif < definition["step_size"]
        if dif >= definition["step_size"]
          new_array = [min - 2*dif, min - dif] 
        end
      else
        # new_array = [param.min - var_diff.to_i, param.min - (2*var_diff).to_i]
        new_array = [param.min - 2*istep, param.min - istep]
      end
    elsif param.min.class == Float
      if (min - fstep*2) < definition["bottom"]
        dif = ((definition["bottom"] - min).abs / 2.0).round(definition["num_decimal"])
        if dif >= definition["step_size"]
          new_array = [ (min - 2*dif).round(definition["num_decimal"]), 
                        (min - dif).round(definition["num_decimal"])]
        end
      else
        # new_array = [ (param.min-var_diff).round(definition["num_decimal"]),
        #               (param.min-2*var_diff).round(definition["num_decimal"]) ]
        new_array = [ (param.min - 2*fstep).round(definition["num_decimal"]), 
                      (param.min - fstep).round(definition["num_decimal"])]
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

end