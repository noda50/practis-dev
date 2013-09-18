require 'pp'
class VarianceAnalysis

  attr_reader :effect_Factor
  attr_reader :e_f
  
  # 
  def initialize(result_set, orthogonal_table, colums)
    @effect_Factor = []

    @m = result_set[:results].values.inject(:+).inject(:+)
    @ss = result_set[:results].values.inject(:+).inject{|ss, n| ss + n**2}
    @numResult = result_set[:results].values.inject(:+).size    
    @ct = @m**2
    @m = @m.to_f / @numResult
    @ct = @ct.to_f / @numResult

    colums.each{|col|
      effFact ={}
      effFact[:name] = col.parameter_name
      effFact[:results] = {}
      result_set[:area].each{|row|
        if !effFact[:results].key?(orthogonal_table[col.id][row])
          effFact[:results][orthogonal_table[col.id][row]] = result_set[:results][row]
        else
          effFact[:results][orthogonal_table[col.id][row]] += result_set[:results][row]
        end
      }
      effFact[:effect] = 0.0
      pp effFact
      effFact[:results].each_value{|v| effFact[:effect] += ((v.inject(:+)**2).to_f / v.size)}
      effFact[:effect] -= @ct
      effFact[:free] = 1 #(2水準なので常に1)
      @effect_Factor.push(effFact) #main effect (v)  = :effect / free 
    }

    # 残差変動
    @s_e = @ss - (@ct + @effect_Factor.inject(0){|sum, ef| sum + ef[:effect]})
    # 残差の自由度
    @e_f = @numResult - 1 # 実験回数(num of combination) - 平均の自由度
    @effect_Factor.each{|ef| @e_f -= ef[:free] }
    @e_v  = @s_e / @e_f
    @effect_Factor.each{|fact| fact[:f_value] = fact[:effect] / @e_v}
  end
end