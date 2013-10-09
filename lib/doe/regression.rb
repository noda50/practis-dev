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

=begin 
p "=== test ==="
include Regression
# sample_excercise

points = []
prgm = Random.new(0)
step = 0.1
order = 1

2.times{
  rmax = 0.0
  axs=[]
  10.times{
    axs.push(prgm.rand(step)+rmax)
    rmax+=step
  }
  points.push(axs)
}
pp points

# p points[0].*(points[0])

target = Vector[0.05, 0.87, 0.94, 0.92, 0.54, -0.11, -0.78, -0.79, -0.89, -0.04]

phi_vectors = []
points.each{|axs|
  tmp = []
  axs.each{|p|
    tmp.push(phi(p, order))
  }
  phi_vectors.push(Matrix.rows(tmp))
  # phi_vectors.push(gausian_phi(p))
}

pp phi_vectors

weighted_vec = []
phi_vectors.each{|pv|
  weighted_vec.push((pv.t*pv).inv*(pv.t*target))
}

CSV.open("./test.csv", "wb"){|csv|
  (0.0..1.0).step(0.01){|x|
    (0.0..1.0).step(0.01){|y|
      csv << [x, y,
              weighted_vec[0].inner_product(phi(x,order))+
              weighted_vec[1].inner_product(phi(y,order))]
    }
  }
}

Gnuplot.open do |gp|
  Gnuplot::SPlot.new( gp ) do |plot|
    
    plot.dgrid3d "20,20"
    plot.xrange "[0.0:1.0]"
    plot.yrange "[0.0:1.0]"
    plot.title  "Regression Example"
    plot.xlabel "x"
    plot.ylabel "y"
    plot.zlabel "z"
    
    x = []
    y = []
    z = []
    (0.0..1.0).step(0.01).collect { |vx|
      (0.0..1.0).step(0.01).collect { |vy|
        x.push(vx)
        y.push(vy)
        z.push(weighted_vec[0].inner_product(phi(vx,order)) +
               weighted_vec[1].inner_product(phi(vy,order)))
      }
    }
    
    plot.data = [
      # Gnuplot::DataSet.new( "sin(x) + sin(y)" ) { |ds|
      #   ds.with = "lines"
      #   ds.title = "String function"
      #   ds.linewidth = 4
      # },    
      Gnuplot::DataSet.new( [x,y,z] ) { |ds|
        ds.with = "lines"
        ds.title = "Regression"
      }
    ]
  end
end
=end