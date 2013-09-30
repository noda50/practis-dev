require 'matrix'
require 'csv'
require 'pp'

module Regression
	include Math

	def phi(x, order=0)
		if order==0 then return Vector[1.0] end
		phi_arr = []
		order.times{|o|
			phi_arr.push(x**o)
		}

		return Vector.elements(phi_arr)
	  # s = 0.1 # ガウス基底の「幅」
	  # return np.append(1, Math.exp(-(x - np.arange(0, 1 + s, s)) ** 2 / (2 * s * s)))
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
2.times{
	rmax = 0.0
	axs=[]
	10.times{
		axs.push(prgm.rand(step)+rmax)
		rmax+=step
	}
	points.push(Vector.elements(axs))
}
pp points

t = Vector[0.05, 0.87, 0.94, 0.92, 0.54, -0.11, -0.78, -0.79, -0.89, -0.04]

phi_vectors = []
points.each{|vec|
	phi_vectors.push(Matrix.rows(vec.map{|e| phi(e,4)}, true))
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
		csv_arr.push(tmp_v)
		csv << csv_arr
	}
}
