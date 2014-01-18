#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'json'

require 'practis'
require 'practis/message'
require 'practis/net'
require 'practis/database'

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

a, b, c = nil, nil, nil

# You can get parameters from argument_hash. This example provides two parameter
# such as "a" and "b".
argument_hash[:parameter_set].each do |parameter|
  case parameter[:name]
  when "v1" then a = parameter[:value].to_f
  when "v2" then b = parameter[:value].to_f
  when "seed" then c = parameter[:value].to_i
  end
end


# pre-process
require 'property_generator'


dirName = "sample/kitakyusyu"
mapfilename = ""
filename = "property.xml"

PropertyGenerator.generate(dirname, mapfilename, filename) # argment



# execute 
include Math
command = 'java -jar work/bin/lib/IteratedPrisonerDilemma.jar ' + a.to_s + @spliter + b.to_s + @spliter + c.to_s


# - - - - - - - - - - - - - - - - - -


# To upload your result, please define variables that is same name with the
# fields you defined. This example defines one result field in the
# configuration named "value".

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
