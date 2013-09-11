class VarianceAnalysis

  attr_reader :effFact_list
  
  # 
  def initialize(result_set, orthogonal_table, colums)
    # combi_size = 0
    @effFact_list = []

    @m = result_set[:results].values.inject(:+).inject(:+)
    @ss = result_set[:results].values.inject(:+).inject{|ss, n| ss + n**2}
    @numResult = result_set[:results].values.inject(:+).size    
    @ct = @m**2
    @m = @m.to_f / @numResult
    @ct = @ct.to_f / @numResult

    colums.each{|col|
      effFact ={}
      effFact[:parameter] = col.parameter_name
      effFact[:results] = {}
      result_set[:area].each{|row|
        if !effFact[:results].key?(orthogonal_table[col.id][row])
          effFact[:results][orthogonal_table[col.id][row]] = result_set[:results][row].inject(:+)
        end
      }
    }

    for col in 0...orthogonal_table.size
      effFact ={}
      effFact[:parameter] = colums[col].parameter_name
      effFact[:results] = {}
      result_set[:area].each{|row|
        if !effFact[:results].key?(orthogonal_table[col][row])
          effFact[:results][orthogonal_table[col][row]] = result_set[:results][row]
        else
          effFact[:results][orthogonal_table[col][row]] += result_set[:results][row]
        end
      }
      effFact[:effect] = 0.0
      effFact[:results].each_value{|v| effFact[:effect] += ((v.inject(:+)**2).to_f / v.size)}
      effFact[:effect] -= @ct
      effFact[:free] = 1 #(2水準なので常に1)
      @effFact_list.push(effFact) #main effect (v)  = :effect / free 
    end

    # 残差変動
    @s_e = @ss - (@ct + @effFact_list.inject(0){|sum, ef| sum + ef[:effect]})
    # 残差の自由度
    @e_f = result_set[:area].size - 1 # 実験回数(num of combination) - 平均の自由度
    @e_v  = @s_e / @e_f
    @effFact_list.each{|fact| fact[:f_value] = fact[:effect] / @e_v}

    # p "s_e: " + @s_e.to_s
    # p "e_f: " + @e_f.to_s
    # p "e_v: " + @e_v.to_s
  end
end