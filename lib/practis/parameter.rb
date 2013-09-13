#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'json'

require 'practis'
require 'practis/parameter_parser'
require 'practis/parameter_scheduler'

module Practis

  #=== an instance of Variable class
  class Parameter

    include Practis

    # a name of the variable.
    attr_reader :name
    # a type of the variable.
    attr_reader :type
    # a value of this parameter
    attr_reader :value

    #=== initialize method.
    #name :: a parameter name.
    #type :: a parameter type.
    #value :: a value of the parameter.
    def initialize(name, type, value)
      @name = chk_arg(String, name)
      @type = string_to_type(chk_arg(String, type))
      @value = chk_arg(@type, value, true)
    end
  end


  #=== a set of Parameter instance
  class ParameterSet

    include Practis

    # An array object of Parameter class.
    attr_accessor :parameter_set
    # The state of the parameter set.
    attr_accessor :state
    # An unique identifier
    attr_reader :uid

    #=== initialize method.
    #uid :: an unique identifier of the parameter set.
    #parameter_set :: an initial parameter set if specified.
    def initialize(uid = nil, parameter_set = nil)
      uid ||= Practis::VariableSet.allocate_new_id
      @uid = chk_arg(Integer, uid)
      @parameter_set = chk_arg(Array, parameter_set, true)
      @parameter_set.each { |p| chk_arg(Parameter, p) }
      @state = PARAMETER_STATE_READY
    end
  end

  #=== Variable that generates Parameters from Pattern.
  class Variable

    include Practis

    # The name of the variable.
    attr_reader :name
    # The type of the variable.
    attr_reader :type
    # The value pattern of this variable. The pattern has to be json string
    # object that is generated by ParameterParser.
    attr_reader :pattern
    # all parameters (should not be modified)
    attr_reader :parameters

    #=== initialize method.
    #name :: a variable name.
    #type :: a variable type.
    #pattern :: a Pattern class object.
    def initialize(name, type, pattern)
      @name = chk_arg(String, name)
      @type = chk_arg(String, type)
      @type = string_to_type(@type)
      @pattern = chk_arg(String, pattern)
      @parameters = []
      pattern_generate
    end

    #=== generate variables with the pattern.
    def pattern_generate
      @parameters.clear
      hash = JSON.parse(pattern, :symbolize_names => true)
      hash.each do |p|
        case p[:type]
        when INCLUDE_RANGE
          get_range_values(p).each { |value|
            @parameters.push(value) unless @parameters.include?(value) }
        when EXCLUDE_RANGE
          get_range_values(p).each { |value|
            @parameters.delete(value) if @parameters.include?(value) }
        when INCLUDE_LIST
          p[:list].each { |list|
            @parameters.push(list) unless @parameters.include?(list) }
        when EXCLUDE_LIST
          p[:list].each { |list|
            @parameters.delete(list) if @parameters.include?(list) }
        end
      end
    end

    #=== generate an array of range value.
    def get_range_values(json)
      range_values = []
      startval = chk_arg(type, json[:start])
      endval = chk_arg(type, json[:end])
      stepval = chk_arg(type, json[:step])
      if startval.nil? || endval.nil? || stepval.nil?
        warn("invalid range pattern. start val: #{startval}, end val: " +
             "#{endval}, step val: #{stepval}")
        return range_values
      end
      startval, endval = endval, startval if startval > endval
      stepval *= -1 if stepval < 0
      while startval <= endval
        range_values.push(startval) unless range_values.include?(startval)
        if startval.kind_of?(Float)
          startval = (BigDecimal(startval.to_s) + BigDecimal(stepval.to_s)).to_f
        else
          startval += stepval
        end
      end
      return range_values
    end

    #=== get a n-th parameter.
    def get_n(n)
      if @parameters.length <= n || n < 0
        warn("invalid index: #{n}, for #{@parameters.length}-length variable.")
        return nil
      end
      return @parameters[n]
    end

    #=== Available parameter length.
    def length
      return @parameters.length
    end

    ## [2013/09/12 H.Matsushima] for design of experiment
    # === 
    def add_parameter(parameter)
      @parameters += parameter
    end
  end

  #=== Variable set.
  class VariableSet

    include Practis

    # Unique IDs pool
    @@id_pool = []  ## [2013/09/07 I.Noda] not used

    # An array of Variable.
    attr_reader :variable_set
    # An approximation method for variables.
    attr_accessor :approximation
    # A scheduler of parameter allocation.
    attr_reader :scheduler

    #=== initialize method.
    #variable_set :: an array of Variable objects.
    #scheduler :: a class name of the scheduler.
    def initialize(variable_set, scheduler = "RoundrobinScheduler")
      @variable_set = chk_arg(Array, variable_set)
      @scheduler = Practis::ParameterScheduler.new(@variable_set, scheduler)
    end

    #=== get a next available parameter set.
    def get_next(newId)
      return nil if (parameter_array =
                     chk_arg(Array, @scheduler.get_parameter_set, true)).nil?
      parameter_set = []
      @variable_set.length.times { |i| parameter_set
        .push(Parameter.new(@variable_set[i].name,
                            type_to_string(@variable_set[i].type),
                            parameter_array[i])) }
      ##[2013/09/07 I.Noda] now, id is given. (taken from database by caller)
      #newId = Practis::VariableSet.allocate_new_id ;
      return ParameterSet.new(newId, parameter_set)
    end

    #=== get a number of available variable set.
    def get_available
      return @scheduler.get_available
    end

    #=== get a total number of variable set.
    def get_total
      return @scheduler.get_total
    end

    ## [2013/09/12 H.Matsushima] add for design of experiment
    #=== use by design of experiment
    def add_variables(name, var_array, old_area, extend_poit)
      @variable_set += chk_arg(Array, var_array)
      new_params = []
      new_params.push({:name => name, :variables => var_array})
      @scheduler.orthogonal_table.extend_table(old_area, extend_poit, new_params)
    end

    ## [2013/09/07 I.Noda] not used anymore
    #=== Allocate a new id for a parameter set.
    #ID must be unique, this method allocate a new ID for a parameter set.
    #id :: if you want to specify a static id, use this arg.
    #returned_value :: an allocated new id.
    def self.allocate_new_id(id=nil)
      new_id = -1
      if id.nil?
        count = 0
        max_parameter = Practis::PARAMETER_ID_DURATION
        while true
          new_id = rand(max_parameter).to_i
          (@@id_pool.push(new_id); break) unless @@id_pool.include?(new_id)
          count += 1
          max_parameter += Practis::PARAMETER_ID_DURATION \
            if count > max_parameter
        end
      else
        new_id = id
        (error("specified ID already exist!"); return nil) \
          if @@id_pool.include?(new_id)
        @@id_pool.push(new_id)
      end
      return new_id
    end
  end
end
