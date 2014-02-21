#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'json'

require 'practis'
require 'practis/message'
require 'practis/net'
require 'practis/database'
require 'pp'


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
EXIT_LIST = [ "NAGHOSHI_CLEAN_CENTER_EXIT", 
              "OLD_MUNICIPAL_HOUSING_EXIT",
              "KAMAKURA_Jr_HIGH_EXIT" ]

#
def createEvacuator(hash=nil, dir, uniqid)
  return nil if hash.nil? || uniqid.nil?
    to_csv = []
    hash.each{|k, v|
      exits = [v["exit_prior"]]
      exits += EXIT_LIST.select{|a| a != v["exit_prior"]}
      div = v["ratio"].to_f
      div = 1.0/3.0 if div < 1.0/3.0

      prefer = (v["total"].to_i*div).ceil
      rest = v["total"].to_i  - prefer

      dist = [prefer, (rest*0.5).to_i, (rest*0.5).to_i]
      dif = v["total"].to_i - dist.inject(:+)
      dist[1] += dif if (dif > 0) && (dif <= (prefer - (rest*0.5).to_i ))

      tmplt = ["TIMEEVERY",k,"18:00:00","18:00:00",1,1]
      
      dist.each_with_index{|v,i|
        arr = tmplt + [v, "DENSITY", exits[i]]
        to_csv.push(arr)
      }
    }

    filename = dir + "/#{uniqid}/gen_#{uniqid}.csv"
    CSV.open(filename, "w") { |csv|
      to_csv.each {|arr| csv << arr }
    }
end
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
  when "z1_prior_exit" then z1l = parameter[:value]
  when "z2_weight" then z2 = parameter[:value].to_f
  when "z2_prior_exit" then z2l = parameter[:value]
  when "z3_weight" then z3 = parameter[:value].to_f
  when "z3_prior_exit" then z3l = parameter[:value]
  when "z4_weight" then z4 = parameter[:value].to_f
  when "z4_prior_exit" then z4l = parameter[:value]
  when "z5_weight" then z5 = parameter[:value].to_f
  when "z5_prior_exit" then z5l = parameter[:value]
  when "z6_weight" then z6 = parameter[:value].to_f
  when "z6_prior_exit" then z6l = parameter[:value]
  when "o5_weight" then o5 = parameter[:value].to_f
  when "o5_prior_exit" then o5l = parameter[:value] 
  when "seed" then seed = parameter[:value].to_i

  #
  # when "property" then a = parameter[:value]

  end
end


# === pre-process ===
require './work/bin/file_generator'

# default (7,328 persons)
zaimoku, ohmachi5 = [1005, 957, 1479, 643, 1385, 1148], 711
# # 10,000 persons
# zaimoku, ohmachi5 = [1371, 1306, 2018, 878, 1890, 1567], 970
# # 7,500 persons
# zaimoku, ohmachi5 = [1029, 979, 1514, 658, 1417, 1175], 728
# # 5,000 persons
# zaimoku, ohmachi5 = [686, 653, 1009, 439, 945, 783], 485
# # 2,500 persons
# zaimoku, ohmachi5 = [343, 326, 505, 219, 472, 392], 243 
# # each 10 persons
# zaimoku, ohmachi5 = [10, 10, 10, 10, 10, 10], 10

uid =  argument_hash[:uid]
origin = "sample/kamakura.practis"
dir = "work/bin/sample/kamakura.practis"
system("-p #{dir}/#{uid}")

h = {
    "ZAIMOKU1" => {
      "total" => zaimoku[0],
      "exit_prior" => z1l,
      "ratio" => z1
    },
    "ZAIMOKU2" => {
      "total" => zaimoku[1],
      "exit_prior" => z2l,
      "ratio" => z2
    },
    "ZAIMOKU3" => {
      "total" => zaimoku[2],
      "exit_prior" => z3l,
      "ratio" => z3
    },
    "ZAIMOKU4" => {
      "total" => zaimoku[3],
      "exit_prior" => z4l,
      "ratio" => z4
    },
    "ZAIMOKU5" => {
      "total" => zaimoku[4],
      "exit_prior" => z5l,
      "ratio" => z5
    },
    "ZAIMOKU6" => {
      "total" => zaimoku[5],
      "exit_prior" => z6l,
      "ratio" => z6
    },
    "OHMACHI5" => {
      "total" => ohmachi5,
      "exit_prior" => o5l,
      "ratio" => o5
    }
  }

p "generate file"
FileGenerator.generate_scenario(dir,"scenario.csv", uid)
FileGenerator.copy_map(dir,"2014_0109_kamakura11-3.xml", origin, uid)
# FileGenerator.generate_gen(dir, "gen.csv", test_ratio, uid)
createEvacuator(h, dir, uid)
FileGenerator.copy_pollution(dir,"output_pollution.csv", origin, uid)
FileGenerator.generate_property(dir, "properties.xml", "2014_0109_kamakura11-3",
                                "gen","output_pollution", uid, "scenario", seed)


# === execute ===
include Math
djava = '-Djava.library.path=work/bin/libs/linux/amd64'
cpath = '-cp work/bin/build/libs/netmas.jar:work/bin/build/libs/netmas-pathing.jar'
command = 'java -Xms1024M -Xms1024M ' + djava + ' ' + cpath + ' main cui'
command = command + ' ' + "work/bin/sample/kamakura.practis/#{uid}/properties_#{uid}.xml _output_#{uid}"
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
