#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'practis'
require 'practis/parameter'
require 'doe/orthogonal_array'
require 'csv'
require 'pp'


module Practis
  class ParameterScheduler

    attr_reader :scheduler

    #=== initialize method.
    #paramDef_set :: a reference to a ParamDefSet object.
    #scheduler_name :: a class name of scheduler.
    def initialize(paramDefList, scheduler_name="RoundrobinScheduler")
      @scheduler = Practis::Scheduler.const_get(scheduler_name)
        .new(paramDefList)
      @mutex = Mutex.new() ;
    end

    def get_paramValues(id=nil)
      @mutex.synchronize{
        if (parameter_array = @scheduler.get_paramValues(id)).nil? ||
            parameter_array.include?(nil)
          return nil
        end
        return parameter_array
      }
      # parameter_array = @scheduler.get_paramValues
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
      attr_reader :paramDefList

      def initialize(paramDefs)
        @paramDefList = chk_arg(Array, paramDefs)
        @current_indexes = []
        @total_indexes = []
        @paramDefList.each do |paramDef|
          chk_arg(Practis::ParamDef, paramDef)
          @current_indexes.push(0)
          @total_indexes.push(paramDef.length)
          debug(paramDef)
        end
      end

      def get_paramValues(id=nil)
        parameter_array = []
        # check whether all of the parameters are allocated?
        if current_indexes[current_indexes.length - 1] >=
            total_indexes[total_indexes.length - 1]
          debug("current: #{current_indexes}")
          debug("total  : #{total_indexes}")
          return nil
        end
        # allocate parameters
        paramDefList.length.times { |i|
          parameter_array.push(paramDefList[i].get_n(current_indexes[i])) }
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
      attr_reader :paramDefList

      def initialize(paramDefs)
        @paramDefList = chk_arg(Array, paramDefs)
        @total_indexes = []
        @paramDefList.each do |paramDef|
          chk_arg(Practis::ParamDef, paramDef)
          @total_indexes.push(paramDef.length)
        end
        @total_number = get_total
        @allocated_numbers = []
        # @available_numbers = (0..@total_number - 1).map {|i| i}
        @available_numbers = @total_number.times.map { |i| i }
        debug("random scheduler initiated, #{@total_number}")
      end

      def get_paramValues(id=nil)
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
        # debug("indexes: #{indexes}")

        # allocate parameters
        paramDefList.length.times do |i|
          parameter_array.push(paramDefList[i].get_n(indexes[i]))
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
        #debug("value_to_indexes: v=#{v}, indexes=#{indexes.inspect}");
        return indexes
      end
    end

    # 
    class DesginOfExperimentScheduler

      include Practis

      attr_reader :current_indexes
      attr_reader :total_indexes
      attr_reader :paramDefList
      attr_reader :oa
      attr_reader :analysis
      attr_reader :current_total

      def initialize(paramDefs)
        @paramDefList = chk_arg(Array, pramDefs)
        # (2013/09/12) written by matsushima ==================
        # assign_list = {}
        # CSV.foreach("lib/doe/ExperimentalDesign.ini") do |r|
        #   if r[1] == "is_assigned"
        #     assign_list[r[0]] = true
        #   elsif r[1] == "is_unassigned"
        #     assign_list[r[0]] = false
        #   end
        # end

        # parameters = []
        # @unassigned = []
        # @total_indexes = []
        # @unassigned_total = []
        # @variable_set.each{|v|
        #   chk_arg(Practis::Variable, v)
        #   @total_indexes.push(v.length)
        #   if assign_list[v.name]
        #     parameters.push({:name => v.name, :variables => v.parameters})
        #   else
        #     @unassigned.push({:name => v.name, :variables => v.parameters})
        #     @unassigned_total.push(v.length)
        #   end
        # }
        
        # @total_number = 1
        # @total_indexes.collect {|t| @total_number *= t}
        # @allocated_numbers = []
        # @available_numbers = @total_number.times.map { |i| i }
        # @unassigned_total_size = 1
        # @unassigned_total.collect{|t| @unassigned_total_size *= t}

        # @oa = OrthogonalArray.new(parameters)
        # @analysis = {:area => @oa.analysis_area[0],
        #             :result_id => {},
        #             :size => @oa.table[0].size*@unassigned_total_size}
        # @v_index = nil
        # @experimentSize = @oa.table[0].size
        
        # @total_experiment = get_total
        # @allocated_numbers = []        
        # @available_numbers = @total_experiment.times.map { |i| i }
        # @current_total = @available_numbers.size
        # (2013/09/12) ==========================================
      end
      #
      def init_doe(file)
        # (2013/09/12) written by matsushima ==================
        assign_list = {}
        CSV.foreach(file) do |r|
          if r[1] == "is_assigned"
            assign_list[r[0]] = true
          elsif r[1] == "is_unassigned"
            assign_list[r[0]] = false
          end
        end

        parameters = []
        @unassigned = []
        @total_indexes = []
        @unassigned_total = []
        @paramDefList.each{|paramDef|
          chk_arg(Practis::ParamDef, paramDef)
          @total_indexes.push(paramDef.length)
          if assign_list[paramDef.name]
            parameters.push({ :name => paramDef.name,
                              :paramDefs => paramDef.paramDefs})
          else
            @unassigned.push({ :name => paramDef.name, 
                               :paramDefs => paramDef.paramDefs})
            @unassigned_total.push(paramDef.length)
          end
        }
        
        @total_number = 1
        @total_indexes.collect {|t| @total_number *= t}
        @allocated_numbers = []
        @available_numbers = @total_number.times.map { |i| i }
        @unassigned_total_size = 1
        @unassigned_total.collect{|t| @unassigned_total_size *= t}

        @oa = OrthogonalArray.new(parameters)
        @analysis = {:area => @oa.analysis_area[0],
                    :result_id => {},
                    :size => @oa.table[0].size*@unassigned_total_size}
        @v_index = nil
        @experimentSize = @oa.table[0].size
        
        @total_experiment = get_total
        @allocated_numbers = []        
        @available_numbers = @total_experiment.times.map { |i| i }
        @current_total = @available_numbers.size
        # (2013/09/12) ==========================================
      end
      
      # get parameter set from paramDefList
      def get_paramValues(id=nil)
        # already allocated all parameters
        if @available_numbers.length <= 0
          debug("no available parameter, \n" +
                "total index num: #{@total_indexes.length}, \n" +
                "total indexes: #{@total_indexes}, \n" +
                "available: #{@available_numbers.length}, \n" +
                "allocated: #{@allocated_numbers.length} \n")
          return nil
        end

        v = @available_numbers.shift
        @v_index = v / @unassigned_total_size
        @allocated_numbers.push(v)
        not_allocate_indexes = value_to_indexes(v % @unassigned_total_size)
        parameter_array = []
        @paramDefList.size.times{ |i|
          unassign_flag = true
          @oa.colums.each{|col|
            if @paramDefList[i].name == col.parameter_name
              parameter_array.push(@oa.get_parameter(@analysis[:area][@v_index], col.id))
              unassign_flag = false
              break
            end
          }
          if unassign_flag
            parameter_array.push(paramDefList[i].get_n(not_allocate_indexes[i]))
          end 
        }

        if !@analysis[:result_id].key?(@analysis[:area][@v_index])
          @analysis[:result_id][@analysis[:area][@v_index]] = []
        end
        @analysis[:result_id][@analysis[:area][@v_index]].push(id)

        return parameter_array
      end

      # 
      def get_available
        return @available_numbers.length
      end

      # 
      def get_total
        # return @experimentSize*@unassigned_total_size
        return @oa.table[0].size*@unassigned_total_size
      end

      #
      def already_allocation(already_id=nil, new_id=nil)
        if already_id.nil? || new_id.nil?
          error("error id is empty:")
          pp @analysis
        end
        flag = false
        @analysis[:result_id].each_value{|arr|
          arr.each_with_index{|v, i|
            if v == new_id
              arr[i] = already_id
              flag = true
              break
            end
          }
          if flag then break end
        }
      end

      def get_v_index
        return @v_index
      end

      # 
      def update_analysis(next_area)
        @analysis[:area] = next_area
        @analysis[:result_id] = {}
        @analysis[:size] = next_area.size*@unassigned_total_size
        @available_numbers += @analysis[:size].times.map { |i| i }
        @total_experiment = get_total
        @current_total = @available_numbers.size
      end

      # return parameter combination indexes
      private
      def get_assignedSet(n = 0)
        arr = Array.new
        for i in 0...@assignedOA.size
          arr.push(@assignedOA[i][n])
        end
        return arr
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
        return indexes
      end
    end
  end
end
