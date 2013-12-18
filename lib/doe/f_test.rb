require 'doe/f_distribution_table'
require 'practis'
require 'pp'

#
class FTest
  include Practis
  include Math

  # 
  def initialize
    @p_sig = 0.005
    @f_disttable = F_DistributionTable.new(@p_sig)
  end

  # 
  def run(results_set, parameter_keys, sql_connector=nil, id_list)
    @mean, @ss, @count = 0, 0, 0
    
    result_array(results_set).each{|results|
      @mean += results.inject(:+)
      @ss += results.map { |x| x*x }.inject(:+)
      @count += results.size
    }

    @ct = @mean * @mean / @count.to_f
    @mean /= @count.to_f

    @effFacts = parameter_keys.map do |parameter_key|
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
      effFact[:effect] = 0.0 if effFact[:effect] < 0.0
      effFact[:free] = 1
      effFact
    end

    @s_e = @ss - (@ct + @effFacts.inject(0) {|sum,ef| sum + ef[:effect]})
    @s_e = 0.0 if @s_e < 0.0
    @e_f = @count - 1
    @effFacts.each do |ef|
      @e_f -= ef[:free]
    end
    
    @e_v = @s_e / @e_f
    @effFacts.each do |fact|
      if !(fact[:effect] / @e_v).nan?
        fact[:f_value] = fact[:effect] / @e_v
      else
        fact[:f_value] = fact[:effect] / @p_sig
      end

      if fact[:f_value] < 0.0
        p "ss: #{@ss}, ct:#{@ct}, s_e: #{@s_e}"
        pp fact[:effect]
      end
    end

    result = {}
    @effFacts.each do |ef|
      result[ ef[:name] ] = ef
      result[ ef[:name] ].delete(:name)
    end

    upload_f_test(sql_connector, results_set, parameter_keys, result, id_list) if !sql_connector.nil?
    return result
  end

  #
  def check_significant(name, f_result)
    return @f_disttable.get_Fvalue(f_result[name][:free], @e_f, f_result[name][:f_value])
  end


  private

  #
  def result_array(results_set)
    results_set.map{|results| results.map{|r| r["value"]} }
  end

  #
  def upload_f_test(sql_connector, results_set, parameter_keys, f_result, id_list)
    msg = {}
    msg[:f_test_id] = getNewFtestId(sql_connector)
    msg[:id_combination] = id_list[:or_ids].sort.to_s
    # msg[:result_set] = results_set.map{|rs| rs.map{|r| r["result_id"]}}.to_s
    parameter_keys.each{|k|
      msg[("range_#{k}").to_sym] = (results_set.map{|r| r[0][k] }.uniq).to_s
      if !f_result[k][:f_value].finite?
        msg[("f_value_of_#{k}").to_sym] = 1024
      else
        msg[("f_value_of_#{k}").to_sym] = f_result[k][:f_value]
      end
      msg[("gradient_of_#{k}").to_sym] = 0.0
    }
    if (retval = sql_connector.insert_record(:f_test, msg).length != 0)
      error("fail to insert new f-test result. #{retval}")
      return -2
    end
    return 0
  end

  #
  def getNewFtestId(sql_connector)
    maxid = sql_connector.read_max(:f_test, 'f_test_id', :integer)
    maxid ||= 0
    debug("maxId: #{maxid}")
    return maxid + 1
  end
end