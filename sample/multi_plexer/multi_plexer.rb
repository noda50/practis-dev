include Math

header_bit_num = 2
bit_num = header_bit_num + 2**header_bit_num

p inputs = bit_num.times.map{|i| rand(2) }

h = header_bit_num.times.map{|i| inputs[i]}.join
p "#{h}, #{("0b" + h).oct}"

p inputs[header_bit_num+("0b" + header_bit_num.times.map{|i| inputs[i]}.join).oct]


