#include Math

module MultiPlexer

	#
	def self.run(bit_num, inputs = nil)
		inputs[bit_num+("0b" + bit_num.times.map{|i| inputs[i]}.join).oct]
	end

	#
	def self.run_continuous_value(bit_num, inputs = nil)
		threshold = 0.5
		inputs = inputs.map{ |i| i < threshold ? 0 : 1 }
		run(bit_num, inputs)
	end

end
