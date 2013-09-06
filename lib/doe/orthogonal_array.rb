require './orthogonal_column'
require 'pp'

# extend 2 levels orthogonal array
class OrthogonalArray

  attr_reader :table
  attr_reader :num_of_factor
  attr_reader :l_size #experiment size
  attr_reader :colums

  # 
  def initialize(parameters)
    level = 2
    @table =[]
    @colums = []
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
  end

  # 
  def extend_table(add_point_case, parameters)
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
        oc.check_alignment(add_point_case, parameters[:variables])
        oc.assign_parameter(old_level, oc.parameters)
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
  # 直交表全体の確認 :TODO modify
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
  # 
  def get_row(row)
    bits = []
    @table.each{|col|
      bits.push(col[row])
    }
    return bits
  end
end
