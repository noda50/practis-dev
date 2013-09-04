class OrthogonalColumn
	include Math

	OUTSIDE_PLUSE = "outside(+)"
	OUTSIDE_MINUS = "outside(-)"
	INSIDE = "inside"
	BOTH_SIDE = "both side"

	attr_reader :level
	attr_reader :digit_num
	attr_reader :corresponds


	# start 2 levels of parameter
	def initialize(initial_parameters)
		@level = initial_parameters.size
		initial_parameters.sort!
		@corresponds = {}
		@digit_num = @level / 2
		for i in 0...@level do
		  bit = ("%0" + @digit_num.to_s + "b") % i
		  @corresponds[bit] = params[i]
		end
	end

	# check digit number 
	def equal_digit_num(old_digit_num) 
	  old_digit_num = @digit_num
	  @digit_num = sqrt(@level).ceil
	  if old_digit_num < @digit_num
	    return true
	  else
	    return false
	  end
	end

	# update digit number
	def padding(old_digit_num, old_level)
	  old_bit_str = "%0" + old_digit_num.to_s + "b"
	  new_bit_str = "%0" + @digit_num.to_s + "b"
	  for i in 0...old_level
	    @corresponds[new_bit_str % i] = @corresponds[old_bit_str % i]
	    @corresponds.delete(old_bit_str % i)
	  end
	end

	# in case of new parameter points, check & alignment parameter in order
	def check_alignment(add_point_case, parameter)
	  case add_point_case
	  when OUTSIDE_PLUSE
	    right_digit_of_max = @corresponds.max_by(&:last)[0]
	    if right_digit_of_max[right_digit_of_max.size - 1] == "1"
	      parameter.sort!
	    else
	      parameter.sort.reverse!
	    end
	  when OUTSIDE_MINUS
	    right_digit_of_min = @corresponds.min_by(&:last)[0]
	    if right_digit_of_min[right_digit_of_max.size - 1] == "0"
	      parameter.sort!
	    else
	      parameter.sort.reverse!
	    end
	  when INSIDE
	    digit_num_of_left_point = @corresponds.max_by { |item| (item[1] < parameter[0]) ? item[1] : -1}[0]
	    if digit_num_of_left_point[digit_num_of_left_point.size - 1] == "0"
	      parameter.sort.reverse!
	    else
	      parameter.sort!
	    end
	  when BOTH_SIDE
	    right_digit_of_max = @corresponds.max_by(&:last)[0]
	    if right_digit_of_max[right_digit_of_max.size - 1] == "1"
	      parameter.sort.reverse!
	    else
	      parameter.sort!
	    end
	  else
	    p "error"
	  end
	  return parameter
	end
end