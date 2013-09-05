# 直交表
class OrthogonalArray

  # アクセサ
  attr_reader :digit_num
  attr_reader :factor
  attr_reader :l_size
  attr_reader :level
  attr_reader :table

  #初期化(直交表の生成)
  #level(水準), factor(因子)
  def initialize(level, factor)

    # 水準
    @level = level
    # 因子
    @factor = factor
    l = 0
    while level**l - 1 < factor
      l += 1
    end
    # 実験回数
    @l_size = level**l
    # 最大割り当て因子数
    @maxNumOfFactor = level**l - 1
    # 直交表生成のための桁数
    @digit_num = @l_size.to_s(2).size - 1
    # 直交表
    @table = Array.new()


    # 前置き基準の生成
    # まずベクトルを生成
    vector = Array.new()

    # ベクトルの数 = @digit_num
    @digit_num.times{
      tmp = Array.new()
      vector.push(tmp)
    }

    for i in 0...@l_size
      j = 0
      sprintf("%0" + @digit_num.to_s + "b", i).split('').each do |ch| 
        vector[j].push(ch.to_i)
        j += 1
      end
    end

    # 与えられたベクトルから，排他的論理和を満たす他のベクトルの生成追加
    # "よくわかる実験計画法"の生成方法にもとづいて実装
    for i in 1..vector.size
      comb = vector.combination(i)
      col = 0
      comb.collect{|set|
        tmp = Array.new()

        for j in 0...set[0].size
          if 1 < set.size then
            sum = 0
            for k in 0...set.size
              sum += set[k][j]
            end
            # 0/1を入れていく
            if sum % 2 == 0 then
              tmp.push(0)
            else
              tmp.push(1)
            end
          else
            tmp.push(set[0][j])
          end
        end

        @table.push(tmp)
      }
    end
  end

  # 直交表にある要素の確認
  def get_OrthogonalTable(row, col)
    return @table[col][row] # 行列が列行の状態
  end

  # 直交表全体の確認
  def show_OrthogonalArray
    for row in 0...@l_size
      for col in 0...@maxNumOfFactor
        print @table[col][row].to_s + "," #列,行の順番
      end
      puts
    end
  end

  #ベクトルの取得
  def get_vector(col)
    return @table[col]
  end

  # col番目のベクトルのrow番目に記述されたn水準のうちの1つを示す値を返す
  def get_level(col, row)
    return @table[col][row]
  end

end
