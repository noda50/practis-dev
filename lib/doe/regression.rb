require 'matrix'
require 'csv'
require 'pp'

module Regression
	include Math


  def do_regression(result_set)
    var_vec = {}
    reg_target = []
    tmp_phi = {}
    @assign_list.each{|k,v| if v then var_vec[k] = []; tmp_phi[k] = nil end }
    reg_target = Vector.elements(reg_target)
    var_vec.each{|k,v|
      tmp_phi[k] = Matrix.rows(v.map{|e| phi(e,1)}, true)
      result_set[:weight][k] = (tmp_phi[k].t*tmp_phi[k]).inverse*(tmp_phi[k].t*reg_target)
    }

    
  end

	# 
	def phi(x, order=0)
		phi_arr = []
    0.upto(order){|o|
      o == 0 ? phi_arr.push(1.0) : phi_arr.push(x**o)
    }
    return Vector.elements(phi_arr)
	end

	#
	def gausian_phi(x, sigma=0.1)
		s=sigma
		gaus_arr = [1.0]
  	(0...(1+s)).step(s){|v| gaus_arr.push(exp(-(x-v)**2/(2*s*s)))}
  	return Vector.elements(gaus_arr)
	end

end