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
