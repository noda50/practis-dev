#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'practis'
require 'practis/parameter'


module Practis
  class ParameterScheduler

    attr_reader :scheduler

    #=== initialize method.
    #variable_set :: a reference to a VariableSet object.
    #scheduler_name :: a class name of scheduler.
    def initialize(variable_set, scheduler_name="RoundrobinScheduler")
      @scheduler = Practis::Scheduler.const_get(scheduler_name)
        .new(variable_set)
      @mutex = Mutex.new() ;
    end

    def get_parameter_set
      @mutex.synchronize{
        if (parameter_array = @scheduler.get_parameter_set).nil? ||
            parameter_array.include?(nil)
          return nil
        end
        return parameter_array
      }
      # parameter_array = @scheduler.get_parameter_set
      # if parameter_array.nil? then return nil
      # elsif parameter_array.include?(nil) then return nil
      # else return parameter_array
      # end
    end

    def get_available
      return @scheduler.get_available
    end

    def get_total
      return @scheduler.get_total
    end
  end

  module Scheduler

    #=== select a parameter in round robin.
    class RoundrobinScheduler

      include Practis

      attr_reader :current_indexes
      attr_reader :total_indexes
      attr_reader :variable_set

      def initialize(variable_set)
        @variable_set = chk_arg(Array, variable_set)
        @current_indexes = []
        @total_indexes = []
        @variable_set.each do |variable|
          chk_arg(Practis::Variable, variable)
          @current_indexes.push(0)
          @total_indexes.push(variable.length)
          debug(variable)
        end
      end

      def get_parameter_set
        parameter_array = []
        # check whether all of the parameters are allocated?
        if current_indexes[current_indexes.length - 1] >=
            total_indexes[total_indexes.length - 1]
          debug("current: #{current_indexes}")
          debug("total  : #{total_indexes}")
          return nil
        end
        # allocate parameters
        variable_set.length.times { |i|
          parameter_array.push(variable_set[i].get_n(current_indexes[i])) }
        # increment
        current_indexes[0] += 1
        current_indexes.length.times do |i|
          if current_indexes[i] >= total_indexes[i]
            unless i + 1 >= current_indexes.length
              current_indexes[i] = 0
              current_indexes[i + 1] += 1
            end
          end
        end
        return parameter_array
      end

      def get_available
        availables = []
        hoge = 1
        multiple = 1
        current_indexes.length.times do |i|
          availables.push(total_indexes[i] - current_indexes[i])
          hoge += (total_indexes[i] - current_indexes[i] - 1) * multiple
          multiple *= total_indexes[i]
        end
        total = 0
        debug("available array: #{availables}, hoge: #{hoge}, mul: #{multiple}")
        availables.each do |available|
          if available > 1
            if total < 1
              total = available
            else
              total *= available
            end
          end
        end
        #return total
        debug("current: #{current_indexes}")
        debug("total  : #{total_indexes}")
        return hoge
      end

      def get_total
        total = 1
        total_indexes.collect {|t| total *= t}
        return total
      end
    end


    #=== select a parameter in random.
    class RandomScheduler

      include Practis

      attr_reader :current_indexes
      attr_reader :total_indexes
      attr_reader :variable_set

      def initialize(variable_set)
        @variable_set = chk_arg(Array, variable_set)
        @total_indexes = []
        @variable_set.each do |variable|
          chk_arg(Practis::Variable, variable)
          @total_indexes.push(variable.length)
        end
        @total_number = get_total
        @allocated_numbers = []
        #@available_numbers = (0..@total_number - 1).map {|i| i}
        @available_numbers = @total_number.times.map { |i| i }
        debug("random scheduler initiated, #{@total_number}")
      end

      def get_parameter_set
        # already allocated all parameters
        if @available_numbers.length <= 0
          debug("no available parameter, total: #{@total_indexes.length}, " +
                "available: #{@available_numbers.length}, " +
                "allocated: #{@allocated_numbers.length}")
          return nil
        end

        # allocate random number
        v = @available_numbers.sample
        @allocated_numbers.push(v)
        @available_numbers.delete(v)
        parameter_array = []
        indexes = value_to_indexes(v)
        debug("indexes: #{indexes}")

        # allocate parameters
        variable_set.length.times do |i|
          parameter_array.push(variable_set[i].get_n(indexes[i]))
        end
        return parameter_array
      end

      def get_available
        return @available_numbers.length
      end

      def get_total
        total = 1
        @total_indexes.collect {|t| total *= t}
        return total
      end

      private
      def value_to_indexes(v)
        indexes = []
        k = v
        divider = @total_number
        @total_indexes.each do |i|
          divider = (divider / i).to_i
          l = (k / divider).to_i
          k -= l * divider
          indexes.push(l)
        end
        debug("value_to_indexes: v=#{v}, indexes=#{indexes.inspect}");
        return indexes
      end
    end
  end
end
