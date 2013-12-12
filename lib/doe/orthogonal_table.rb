require 'active_record'
require 'pp'


module OrthogonalTable
	
  # 
	def self.generation_orthogonal_table(input)
		level = 2
		table = []

		l = 0
    l += 1 while level**l - 1 < input.length

    l_size = level**l
    max_assign_factor = level**l - 1
    vector = []
    (l_size.to_s(2).size - 1).times{ vector.push([]) }

    for i in 0...l_size
      j = 0
      sprintf("%0" + (l_size.to_s(2).size - 1).to_s + "b", i).split('').each do |ch| 
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
        table.push(tmp)
      }
    end

		return table
	end

  # 
	def self.generate_area(sql_connector, id_list, new_param, parameter)
    new_rows = []
    add_point_case = new_param[:case]
    new_bits =[]
    id=nil

    # scalability problem (load new_rows on memory)
    condition = [:or]
    condition += id_list.map{|i| [:eq, [:field, "id"], i]}
    old_rows = sql_connector.read_record(:orthogonal, condition)
    
    orCond = [:or]
    new_param[:param][:paramDefs].each{|v|
      bit = parameter[:correspond].key(v)
      new_bits.push(bit)
      orCond.push([:eq, [:field, new_param[:param][:name]], bit])
    }

    condition = [:or]
    old_rows.each {|r|
      andCond = [:and]
      r.each{|k, v|
        if k != "id" and k != "run" and k != new_param[:param][:name]
          andCond.push([:eq, [:field, k], v])
        end
      }
      andCond.push(orCond)
      condition.push(andCond)
    }
    new_rows = sql_connector.read_record(:orthogonal, condition)

    old_lower_value_rows = []
    old_upper_value_rows = []
    old_lower_value = nil
    old_upper_value = nil
    old_rows.each{ |row|
      if old_lower_value.nil? # old lower parameter
        old_lower_value_rows.push(row["id"])
        old_lower_value = parameter[:correspond][row[new_param[:param][:name]]]
      else
        if parameter[:correspond][row[new_param[:param][:name]]] < old_lower_value
          old_lower_value_rows.clear
          old_lower_value_rows.push(row["id"])
          old_lower_value = parameter[:correspond][row[new_param[:param][:name]]]
        elsif parameter[:correspond][row[new_param[:param][:name]]] == old_lower_value
          old_lower_value_rows.push(row["id"])
        end
      end
      
      if old_upper_value.nil? # old upper parameter
        old_upper_value_rows.push(row["id"])
        old_upper_value = parameter[:correspond][row[new_param[:param][:name]]]
      else
        if old_upper_value < parameter[:correspond][row[new_param[:param][:name]]]
          old_upper_value_rows.clear
          old_upper_value_rows.push(row["id"])
          old_upper_value = parameter[:correspond][row[new_param[:param][:name]]]
        elsif old_upper_value == parameter[:correspond][row[new_param[:param][:name]]]
          old_upper_value_rows.push(row["id"])
        end
      end
    }

    new_lower_value_rows = []
    new_upper_value_rows = []
    new_lower_value = nil
    new_upper_value = nil
    new_rows.each{ |row|
      if new_lower_value.nil? # new lower parameter
        new_lower_value_rows.push(row["id"])
        new_lower_value = parameter[:correspond][row[new_param[:param][:name]]]
      else
        if parameter[:correspond][row[new_param[:param][:name]]] < new_lower_value
          new_lower_value_rows.clear
          new_lower_value_rows.push(row["id"])
          new_lower_value = parameter[:correspond][row[new_param[:param][:name]]]
        elsif parameter[:correspond][row[new_param[:param][:name]]] == new_lower_value
          new_lower_value_rows.push(row["id"])
        end
      end
      
      if new_upper_value.nil? # new upper parameter
        new_upper_value_rows.push(row["id"])
        new_upper_value = parameter[:correspond][row[new_param[:param][:name]]]
      else
        if new_upper_value < parameter[:correspond][row[new_param[:param][:name]]]
          new_upper_value_rows.clear
          new_upper_value_rows.push(row["id"])
          new_upper_value = parameter[:correspond][row[new_param[:param][:name]]]
        elsif new_upper_value == parameter[:correspond][row[new_param[:param][:name]]]
          new_upper_value_rows.push(row["id"])
        end
      end
    }

    generated_area = []
    case add_point_case
    when "inside"
      # (new_lower, new_upper)
      generated_area.push(new_rows.map{ |r| r["id"] })
      # between (old_lower, new_lower) in area
      generated_area.push(old_lower_value_rows + new_lower_value_rows)
      # between (old_upper, new_upper) in area
      generated_area.push(old_upper_value_rows + new_upper_value_rows)
    when "both side" # TODO
      # between (old_lower, new_lower) in area
      generated_area.push(old_lower_value_rows + new_lower_value_rows)
      # between (old_upper, new_upper) in area
      generated_area.push(old_upper_value_rows + new_upper_value_rows)
      # (new_lower, new_upper)
      # generated_area.push(new_rows.map{ |r| r["id"] })
    when "outside(+)"
      # (new_lower, new_upper)
      generated_area.push(new_rows.map{ |r| r["id"] })
      # new area between (old_upper, new_lower)
      generated_area.push(old_upper_value_rows + new_lower_value_rows)
    when "outside(-)"
      # (new_lower, new_upper)
      generated_area.push(new_rows.map{ |r| r["id"] })
      # new area between (new_upper, old_lower)
      generated_area.push(new_upper_value_rows + old_lower_value_rows)
    else
      p "create NO area for analysis"
    end
    
    return generated_area
	end
end