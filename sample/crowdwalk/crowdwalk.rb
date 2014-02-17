#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'json'

require 'practis'
require 'practis/message'
require 'practis/net'
require 'practis/database'
require 'pp'

#
def istEvacuator(div=1.0/3.0, list, total=100)
  if div.nil? || div < (1.0/3.0)
    div = 1.0/3.0
  else
    div = div.to_f
  end

  prefer = (total*div).ceil
  rest = total - prefer

  dist = [prefer, (rest*0.5).to_i, (rest*0.5).to_i]
  dif = total - dist.inject(:+)

  dist[1] += dif if (dif > 0) && (dif <= (prefer - (rest*0.5).to_i ))
  ret = {}
  dist.each_with_index{|v,i| ret[list[i]] = v }
  return ret
end


# This code is a sample to execute an executable on practis. The functionality
# quite simply calcuates exp(-(x ^ 2 + y ^ 2)).

# Executor provides a parameter ID, an allocated parameter set, a manager IP
# address and names of result fileds.

# Template from here ###########################################################
include Practis
argument_hash = nil
begin
  exit if (argument_hash = parse_executor_arguments(ARGV)).nil?
rescue Exception => e
  error("fail to prepare practis execution. #{e.message}")
  error(e.backtrace)
  raise e
end
# Template to here #############################################################

# From here, you can run any programs!
# Of couse, you need not to use this template. Executor just forks a process. If
# you don't want to be disturbed by them, you can run Java or Python program
# from here using "system" such as "system('java -cp . yourprog.jar')".

z1, z1l, = nil, nil 
z2, z2l, = nil, nil 
z3, z3l, = nil, nil 
z4, z4l, = nil, nil 
z5, z5l, = nil, nil 
z6, z6l, = nil, nil 
o5, o5l, = nil, nil 
seed = nil

# You can get parameters from argument_hash. This example provides two parameter
# such as "a" and "b".
argument_hash[:parameter_set].each do |parameter|
  case parameter[:name]
  when "z1_weight" then z1 = parameter[:value].to_f
  when "z1_prior_exit" then z1l = parameter[:value].to_a
  when "z2_weight" then z2 = parameter[:value].to_f
  when "z1_prior_exit" then z2l = parameter[:value].to_a
  when "z3_weight" then z3 = parameter[:value].to_f
  when "z1_prior_exit" then z3l = parameter[:value].to_a
  when "z4_weight" then z4 = parameter[:value].to_f
  when "z1_prior_exit" then z4l = parameter[:value].to_a
  when "z5_weight" then z5 = parameter[:value].to_f
  when "z1_prior_exit" then z5l = parameter[:value].to_a
  when "z6_weight" then z6 = parameter[:value].to_f
  when "z1_prior_exit" then z6l = parameter[:value].to_a
  when "o5_weight" then o5 = parameter[:value].to_f
  when "z1_prior_exit" then o5l = parameter[:value].to_a 
  when "seed" then seed = parameter[:value].to_i

  #
  # when "property" then a = parameter[:value]

  #
  # when "z1_a" then z1_a = parameter[:value].to_f
  # when "z1_b" then z1_b = parameter[:value].to_f
  # when "z2_a" then z2_a = parameter[:value].to_f
  # when "z2_b" then z2_b = parameter[:value].to_f
  # when "z3_a" then z3_a = parameter[:value].to_f
  # when "z3_b" then z3_b = parameter[:value].to_f
  # when "z4_a" then z4_a = parameter[:value].to_f
  # when "z4_b" then z4_b = parameter[:value].to_f
  # when "z5_a" then z5_a = parameter[:value].to_f
  # when "z5_b" then z5_b = parameter[:value].to_f
  # when "z6_a" then z6_a = parameter[:value].to_f
  # when "z6_b" then z6_b = parameter[:value].to_f
  # when "o5_a" then o5_a = parameter[:value].to_f
  # when "o5_b" then o5_b = parameter[:value].to_f
  
  end
end


# === pre-process ===
require './work/bin/file_generator'
uid =  argument_hash[:uid]

dir = "work/bin/sample/kamakura.practis"




test_ratio = [0.1, 0.8, 0.1,
              0.05, 0.9, 0.05,
              0.2, 0.3, 0.5,
              0.4, 0.5, 0.1,
              0.6, 0.1, 0.3,
              0.01, 0.45, 0.54,
              0.2, 0.7, 0.1]
FileGenerator.generate_scenario(dir,"scenario.csv", uid)
FileGenerator.copy_map(dir,"2014_0109_kamakura11-3.xml", uid)
FileGenerator.generate_gen(dir, "gen.csv", test_ratio, uid)
FileGenerator.copy_pollution(dir,"output_pollution.csv", uid)
FileGenerator.generate_property(dir, "properties.xml", "2014_0109_kamakura11-3",
                                "gen","output_pollution", uid, "scenario", seed)


# === execute ===
include Math
djava = '-Djava.library.path=work/bin/libs/linux/amd64'
cpath = '-cp work/bin/build/libs/netmas.jar:work/bin/build/libs/netmas-pathing.jar'
command = 'java -Xms3072M -Xms3072M ' + djava + ' ' + cpath + ' main cui'
command = command + ' ' + "work/bin/sample/kamakura.practis/properties_#{uid}.xml _output_#{uid}"
# value = `#{command}`.chomp.to_f
# debugpath = ' > ~/cw_log.txt'
# command = command + debugpath
p "execute command"
p command
system(command)
# - - - - - - - - - - - - - - - - - -


# To upload your result, please define variables that is same name with the
# fields you defined. This example defines one result field in the
# configuration named "value".

io = File.open("_output_#{uid}.json", 'r')
parsed = JSON.load(io)
pp parsed
value = parsed["tick"].to_f

#value = se.examine



# Template from here ###########################################################
begin
  fields = {}
  argument_hash[:result_fields].each { |f|
    fields[f[:name].to_sym] = eval(f[:name]) }
  argument_hash[:results] = fields
  exit if upload_result(argument_hash) < 0
rescue Exception => e
  error("fail to upload the result. #{e.message}")
  error(e.backtrace)
  raise e
end
# Template to here #############################################################
