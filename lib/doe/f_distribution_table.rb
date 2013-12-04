# -*- coding: utf-8 -*-
require 'csv' # csvライブラリ

class F_DistributionTable

  def initialize(alpha = 0.01)
    @f_table = Array.new()

    CSV.foreach("lib/doe/f_dist_" + alpha.to_s + ".csv") { |row|
      @f_table.push(row)
    }

    @f_table.each_index do |i|
      @f_table[i].each_index do |j|
        @f_table[i][j] =@f_table[i][j].to_f
      end
    end
  end

  def readfile()

  end

  # F検定の値を取得
#  def get_Fvalue(free, free_e)
#    return @f_table[free_e - 1][free - 1]
#  end

  # F検定によりvfが有意or残差と同程度であるなどの
  def get_Fvalue(free, free_e, vf)
#    p @f_table
    if vf > @f_table[free_e - 1][free - 1] then
      return true
    else
      return false
    end
  end

end