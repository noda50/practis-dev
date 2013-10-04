require 'matrix'
require 'csv'
require 'pp'

module Regression
	include Math

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

	def regress(x, y, degree)
		x_data = x.map { |xi| (0..degree).map { |pow| (xi**pow).to_f } }
	 
		mx = Matrix[*x_data]
		my = Matrix.column_vector(y)
	 
		((mx.t * mx).inv * mx.t * my).transpose.to_a[0]
	end

	def sample_excercise
		v_x = Vector[0.02, 0.12, 0.19, 0.27, 0.42, 0.51, 0.64, 0.84, 0.88, 0.99]
		v_y = Vector[0.01, 0.15, 0.22, 0.30, 0.39, 0.50, 0.61, 0.87, 0.91, 0.98]
		t = Vector[0.05, 0.87, 0.94, 0.92, 0.54, -0.11, -0.78, -0.79, -0.89, -0.04]

		est_x = Matrix.rows(v_x.map{|e| phi(e,4)}, true)
		est_y = Matrix.rows(v_y.map{|e| phi(e,4)}, true)
		w_x = (est_x.t*est_x).inverse*(est_x.t*t)
		w_y = (est_y.t*est_y).inverse*(est_y.t*t)

		CSV.open("./out.csv", "wb"){|csv|
			(0.0..1.0).step(0.01){|e|
				csv << [e, e, w_x.inner_product(phi(e,4))+w_y.inner_product(phi(e,4))]
			}
		}
	end
end

p "=== test ==="
include Regression
# sample_excercise

points = []
prgm = Random.new(0)
step = 0.1

rmax = 0.0

10.times{
	axs=[]
	2.times{
		axs.push(prgm.rand(step)+rmax)
	}
	rmax+=step
	points.push(Vector.elements(axs))
}
pp points

# p points[0].*(points[0])

t = Vector[0.05, 0.87, 0.94, 0.92, 0.54, -0.11, -0.78, -0.79, -0.89, -0.04]

phi_vectors = []
points.each{|p|
	phi_vectors.push(phi(p,1))
	# phi_vectors.push(gausian_phi(p))
}

weighted_vec = []
phi_vectors.each{|pv|
	weighted_vec.push((pv.t*pv).inv*(pv.t*t))
}

CSV.open("./test.csv", "wb"){|csv|
	(0.0..1.0).step(0.01){|e|
		tmp_v = 0.0
		csv_arr =[]
		weighted_vec.each{|wv|
			tmp_v += wv.inner_product(phi(e,4))
			csv_arr.push(e)
		}
		csv_arr.push(tmp_v/weighted_vec.size)
		csv << csv_arr
	}
}

# betas = regress([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
#                 [1, 6, 17, 34, 57, 86, 121, 162, 209, 262, 321],
#                 2)
# pp betas                 
# exit(0)
