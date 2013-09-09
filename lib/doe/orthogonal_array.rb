require './orthogonal_column'
require 'pp'

# extend 2 levels orthogonal array
class OrthogonalArray

  attr_reader :table
  attr_reader :num_of_factor
  attr_reader :l_size #experiment size
  attr_reader :colums
  attr_reader :analysis_area

  # 
  def initialize(parameters)
    level = 2
    @table =[]
    @colums = []
    @analysis_area = []
    @num_of_factor = parameters.size

    l = 0
    l += 1 while level**l - 1 < @num_of_factor

    @l_size = level**l
    @max_assign_factor = level**l - 1
    
    vector = []
    (@l_size.to_s(2).size - 1).times{ vector.push([]) }

    for i in 0...@l_size
      j = 0
      sprintf("%0" + (@l_size.to_s(2).size - 1).to_s + "b", i).split('').each do |ch| 
        vector[j].push(ch)
        j += 1
      end
    end

    for i in 1..vector.size
      comb = vector.combination(i)
      col = 0
      comb.collect{|set|
        tmp = []
        for j in 0...set[0].size
          if 1 < set.size then
            sum = 0
            for k in 0...set.size
              sum += set[k][j].to_i(2)
            end
            tmp.push((sum % 2 == 0) ? "0" : "1" )# 0/1を入れていく
          else
            tmp.push(set[0][j])
          end
        end
        @table.push(tmp)
      }
    end

    id = 0
    parameters.each{|prm|
      oc = OrthogonalColumn.new(id , prm[:name], prm[:variables])
      @colums.push(oc)
      id += 1
    }

    area = []
    for i in 0...@table[0].size
      area.push(i)
    end
    @analysis_area.push(area)
  end

  # 
  def extend_table(id_set, add_point_case, parameters)
    old_level = 0
    old_digit_num = 0
    twice = false
    @colums.each{ |oc|
      if oc.parameter_name == parameters[:name]
        old_level = oc.level        
        oc.update_level(parameters[:variables].size)
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
        oc.assign_parameter(old_level, add_point_case, parameters[:variables])
        break
      end
    }
    if twice 
      @colums.each{|oc|
        if oc.parameter_name != parameters[:name]
          copy = []
          @table[oc.id].each{ |b| copy.push(b) }
          @table[oc.id] += copy
        end
      }
    end
    # generate new analysis area

  end

  # 
  def generate_new_analysis_area(old_rows, new_rows, add_point_case, exteded_column)
    old_lower_value_rows, old_upper_value_rows = []
    old_lower_value, old_upper_value = nil
    old_rows.each{|row|
      # old lower parameter
      if old_lower_value.nil?
        old_lower_value_rows.push(row)
        old_lower_value = exteded_column[@table[exteded_column.id][row]]
      else
        if exteded_column[@table[exteded_column.id][row]] <= old_lower_value
          old_lower_value_rows.push(row)
          old_lower_value = exteded_column[@table[exteded_column.id][row]]
        end
      end
      # old upper parameter
      if old_upper_value.nil?
        old_upper_value_rows.push(row)
        old_upper_value = exteded_column[@table[exteded_column.id][row]]
      else
        if old_upper_value <= exteded_column[@table[exteded_column.id][row]]
          old_upper_value_rows.push(row)
          old_upper_value = exteded_column[@table[exteded_column.id][row]]
        end
      end
    }

    # =====================================
    # TODO :modify
    new_lower_value_rows, new_upper_value_rows = []
    new_lower_value, new_upper_value = nil
    new_rows.each{
      # new lower parameter
      if new_lower_value.nil?
        new_lower_value_rows.push(row) # TODO :modify
        new_lower_value = exteded_column[@table[exteded_column.id][row]]
      else
        if exteded_column[@table[exteded_column.id][row]] <= new_lower_value
          new_lower_value_rows.push(row)
          new_lower_value = exteded_column[@table[exteded_column.id][row]]
        end
      end
      # new upper parameter
      if new_upper_value.nil?
        new_upper_value_rows.push(row) 
        new_upper_value = exteded_column[@table[exteded_column.id][row]]
      else
        if new_upper_value <= exteded_column[@table[exteded_column.id][row]]
          new_upper_value_rows.push(row)
          new_upper_value = exteded_column[@table[exteded_column.id][row]]
        end
      end
    }
    # =====================================

    case add_point_case
    when "outside(+)"
      # (new_lower, new_upper)
      new_area = []
      area.each { |e| new_area.push(@table.size + e) }
      @analysis_area.push(new_area)
      # new area between (old_upper, new_lower)
      @analysis_area.push(old_upper_value_rows + new_lower_value_rows)
    when "outside(-)"
      # (new_lower, new_upper)
      new_area = []
      area.each { |e| new_area.push(@table.size + e) }
      @analysis_area.push(new_area)
      # new area between (new_upper, old_lower)
      @analysis_area.push(new_upper_value_rows + old_lower_value_rows)
    when "inside"
      # (new_lower, new_upper)
      new_area = []
      area.each { |e| new_area.push(@table.size + e) }
      @analysis_area.push(new_area)
      # between (old_lower, new_lower) in area
      @analysis_area.push(old_lower_value_rows + new_lower_value_rows)
      # between (old_upper, new_upper) in area
      @analysis_area.push(old_upper_value_rows + new_upper_value_rows)
    when "both side" # TODO
      new_area = []
      # get max, min of parameter
      # (new_lower, old_lower(min)
      new_area = []
      @analysis_area.push(new_area)
      # (old_upper(max), new_upper)
      @analysis_area.push(new_area)
    else
      p "create NO area for analysis"
    end
  end

  # col番目のベクトルのrow番目に記述されたn水準のうちの1つを示す値を返す
  def get_index(col, row)
    return @table[col][row].to_i(2)
  end
  #
  def get_parameter(row, col)
    return @colums[col].get_parameter(@table[col][row])
  end
  # 
  def get_parameter_set(row)
    p_set = []
    @colums.each{ |oc|
      p_set.push(get_parameter(row, oc.id))
    }
    return p_set
  end
  #
  def get_assigned_parameters
    show = []
    for i in 0...@table[0].size
      show.push(get_parameter_set(i))
    end
    return show
  end
  # 直交表全体の確認
  def get_table
    table_info = []
    @table[0].size.times{ table_info.push([]) }
    for i in 0...@table.size
      for j in 0...@table[i].size
        table_info[j].push(table[i][j])
      end
    end
    return table_info
  end
  #ベクトルの取得
  def get_vector(col)
    return @table[col]
  end
  # return array of bit strings
  def get_row(row)
    bits = []
    @table.each{|col|
      bits.push(col[row])
    }
    return bits
  end
end
