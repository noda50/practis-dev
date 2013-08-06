require 'csv' # csvライブラリ

# 分散分析をする
class VarianceAnalysis

  attr_reader :ss, :ct, :e, :effFact, :f, :f_e

  # 初期化
  # assignment = 割り付け
  # result = {[0, 1,..., ] => [R1, R2,..., Rm], [] => [], ...}
  # params = [A, B,..., N]パラメータ名
  # 水準数
  def initialize(assignment, result, params, levels)

    # 実験結果の数
    @numResult = 0
    # 結果に対する全体平均
    @m = 0.0

    # 全変動(結果の2乗和)
    @ss = 0

    result.each{|item|
      for i in 0...item.size
        @m += item[i]
        @ss += item[i]**2
        @numResult += 1
      end
    }

    @ct = @m**2
    @m /= @numResult

    #コレクションターム
    @ct /= @numResult

    # まず各因子の水準ごとのデータ和を計算
    @effFact = Hash::new
    assignment.each_key{|k|
      @effFact[k] = Array.new(levels){ |n| 0 }
    }

    @effFact.each_key{ |k|
      if true || (result.size == assignment[k].size) 
        # print "**********************************"
        for j in 0...result.size# for j in 0...assignment[k].size #=4
          sum = 0
          for h in 0...result[j].size #=2
            sum += result[j][h]
          end

          @effFact[k][assignment[k][j]] += sum
        end
      end
    }

    # 主効果の算出から残差変動を計算
    @m_eff = Hash::new
#    @m_eff = Array.new(@effFact.size){|n| 0} # ハッシュに変更
    @s_e = @ss - @ct

    for i in 0...@effFact.size
      tmp = 0.0
      for j in 0...@effFact[params[i]].size
        tmp += @effFact[params[i]][j]**2
#        @m_eff[i] += @effFact[params[i]][j]**2
      end
      @m_eff[params[i]] = tmp / (@numResult/@effFact[params[i]].size) - @ct
#      @m_eff[i] = @m_eff[i] / (@numResult/@effFact[params[i]].size) - @ct
#      @s_e -= @m_eff[i]
      @s_e -= @m_eff[params[i]]
    end

    # ---ここから自由度---
    # 変動ssを自由度fで割ったもの
    @v = Hash::new

    # 残差の自由度
    @f_e = @numResult - 1 # 実験回数 - 平均の自由度(常に1)

    for i in 0...@effFact.size
      @f_e -= levels - 1 # 各要因の自由度は 水準 - 1(今，水準数が固定)
#      @v[i] = @m_eff[i] / (levels - 1)
      @v[params[i]] = @m_eff[params[i]] / (levels - 1)
    end

    if @f_e >= 1 
      # 残差のV
      @v_e = @s_e / @f_e

      # Fはvをv_eで割ったもの
      # @f = Array.new(@effFact.size) # ハッシュに変更
      @f = Hash::new

      for i in 0...@effFact.size
  #      @f[i] = @v[i] / @v_e
        @f[params[i]] = @v[params[i]] / @v_e
      end
    end
    # ---ここまで---

  end

  #
  def getAverage
    # パラメータ範囲と平均値があればOK
    return @m
  end


end