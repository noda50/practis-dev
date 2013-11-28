require 'doe/f_distribution_table'
require 'pp'

#
class FTest

  attr_reader :effect_Factor
  attr_reader :e_f
  
  # 
  def initialize
    @f_disttable = F_DistributionTable.new(0.01)
  end

  # 
  def run(results_set, parameter_keys)
    @mean, @ss, @count = 0, 0, 0
    
    result_array(results_set).each{|results|
      @mean += results.inject(:+)
      @ss += results.map { |x| x*x }.inject(:+)
      @count += results.size
    }

    @ct = @mean * @mean / @count.to_f
    @mean /= @count.to_f

    effFacts = parameter_keys.map do |parameter_key|
      effFact ={}
      effFact[:name] = parameter_key
      effFact[:results] = {}

      results_set.each do |results|
        results.each do |r|
          effFact[:results][r[parameter_key]] ||= []
          effFact[:results][r[parameter_key]].push(r["value"])
        end
      end

      effFact[:effect] = 0.0
      effFact[:results].each_value do |v|
        effFact[:effect] += (v.inject(:+) ** 2).to_f / v.size
      end
      effFact[:effect] -= @ct
      effFact[:free] = 1
      effFact
    end

    @s_e = @ss - (@ct + effFacts.inject(0) {|sum,ef| sum + ef[:effect]})
    @e_f = @count - 1
    effFacts.each do |ef|
      @e_f -= ef[:free]
    end
    p @s_e,@e_f
    @e_v = @s_e / @e_f
    effFacts.each do |fact|
      fact[:f_value] = fact[:effect] / @e_v
    end

    result = {}
    effFacts.each do |ef|
      result[ ef[:name] ] = ef
      result[ ef[:name] ].delete(:name)
    end

    return result
  end
  #
  def check_significant(name)
    effect_Factor.each{|ef|
      return @f_disttable.get_Fvalue(ef[:name][:free], @e_f, ef[:f_value]) if ef[:name] == name
    }
    return nil
  end
  #
  def get_f_value(name)
    @effect_Factor.each{|ef|
      if ef[:name] == name
        return ef[:f_value]
      else
        return 0.0
      end
    }
  end

  private

  def result_array(results_set)
    results_set.map{|results| results.map{|r| r["value"]} }
  end
end