#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'practis'
require 'practis/parameter'
require 'doe/orthogonal_array'
require 'doe/orthogonal_table'
require 'doe/f_test'
require 'doe/doe_parameter_generator'
require 'csv'
require 'pp'
require 'pry'


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
=begin
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
        @paramDefList = chk_arg(Array, paramDefs)
        # move to method "init_doe"
      end
      #
      def init_doe(assign_list)
        @assign_list = assign_list
        parameters = []
        @unassigned = []
        @total_indexes = []
        @unassigned_total = []

        @paramDefList.each{|paramDef|
          chk_arg(Practis::ParamDef, paramDef)
          @total_indexes.push(paramDef.length)
          if @assign_list[paramDef.name]
            parameters.push({ :name => paramDef.name, :paramDefs => paramDef.values})
          else
            @unassigned.push({ :name => paramDef.name, :paramDefs => paramDef.values})
            @unassigned_total.push(paramDef.length)
          end
        }
        
        @allocated_numbers = []
        @unassigned_total_size = 1
        @unassigned_total.collect{|t| @unassigned_total_size *= t}

        @oa = OrthogonalArray.new(parameters)
        @analysis = {:area => @oa.analysis_area[0],
                    :result_id => {},
                    :size => @oa.table[0].size*@unassigned_total_size}
        @v_index = nil
        @experimentSize = @oa.table[0].size
        
        @total_experiment = get_total
        @total_number = @total_experiment
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
        not_allocate_indexes = unassigned_value_to_indexes(v % @unassigned_total_size)
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
            parameter_array.push(@paramDefList[i].get_n(not_allocate_indexes[i]))
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
        return @oa.table[0].size*@unassigned_total_size
      end

      def get_v_index
        return @v_index
      end
      
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

      private
      def unassigned_value_to_indexes(v)
        indexes = []
        k = v
        divider = @unassigned_total_size
        @total_indexes.each_with_index{ |n, i|
          if @assign_list[@paramDefList[i].name]
            indexes.push(0)
          else
            divider = (divider / n).to_i
            l = (k / divider).to_i
            k -= l * divider
            indexes.push(l)  
          end
        }
        return indexes
      end
    end
=end
    # 
    class DOEScheduler
      include Practis
      include OrthogonalTable
      include Math

      attr_reader :current_indexes
      attr_reader :total_indexes
      attr_reader :paramDefList
      attr_reader :eop # end_of_parameters

      #
      def initialize(paramDefs)
        @paramDefList = chk_arg(Array, paramDefs)
        @f_test=FTest.new
        @eop = false
        @extending = false
        @debugFlag = false
      end

      # 
      def init_doe(sql_connector, table, doe_definitions)
        @sql_connector = sql_connector
        @definitions = doe_definitions
        @run_id_queue = []
        @f_test_queue = []
        @generation_queue = []
        @current_qcounter = 0

        @epsilon = @definitions.key?("epsilon") ? @definitions["epsilon"] : 0.2
        # srand(0)
        @prng = Random.new(0)
        DOEParameterGenerator.set_step_size(@definitions)
        
        @parameters = {}
        @total_indexes = []
        @unassigned = []
        @unassigned_total = []
        @allocated_num = 0

        @v_index = nil

        # parameter assign to table
        @paramDefList.each_with_index{|paramDef, i|
          chk_arg(Practis::ParamDef, paramDef)
          @total_indexes.push(paramDef.length)
          if @definitions[paramDef.name]["is_assigned"]
            @parameters[paramDef.name] = {column_id: i, correspond: {}, paramDefs: paramDef.values.sort}
          else
            @unassigned.push({ :name => paramDef.name, :paramDefs => paramDef.values})
            @unassigned_total.push(paramDef.length)
          end
        }
        @parameters.each{|name, param|
          arr = table[param[:column_id]].uniq
          arr.each_with_index{|bit, i|
            param[:correspond][bit] = param[:paramDefs][i]
          }
        }
        # init list
        h = generate_id_data_list(table[0].size.times.map{ |i| i+1 }, "outside", 1.0, @parameters.keys)
        @run_id_queue.push(h)

        upload_initial_orthogonal_db(table)

        @unassigned_total_size = 1
        if !@unassigned_total.empty?
          @unassigned_total.collect{|t| @unassigned_total_size *= t}
        end
        @total_number = get_total   
        @available_numbers = get_total.times.map { |i| i } 
      end
      
      #
      def get_paramValues(id=nil)
        if @available_numbers.length <= 0
          if !@run_id_queue.empty?
            count = @run_id_queue[0][:or_ids].inject(0){|sum, oid| sum + @run_id_queue[0][oid].size}
            if count >= @run_id_queue[0][:or_ids].size * @unassigned_total_size
              # dup check
              chk = @run_id_queue.shift
              # dup = @f_test_queue.find{|test| test[:or_ids].sort == chk[:or_ids].sort }
              if @f_test_queue.empty? ||  @f_test_queue.find{|test| test[:or_ids].sort == chk[:or_ids].sort }.nil?#dup.nil?
                @f_test_queue.push(chk) if !check_duplicate_f_test(chk)
              end
              # dup check (end)
              return nil
            elsif count == 0
              @available_numbers = get_total.times.map { |i| i }  
            end
          else
            return nil
          end
        end

        return nil if @extending
        
        v = @available_numbers.shift
        @v_index = v / @unassigned_total_size
        @allocated_num += 1
        not_allocate_indexes = unassigned_value_to_indexes(v % @unassigned_total_size)
        parameter_array = []
        id_index = @run_id_queue[0][:or_ids][@v_index]
        ret = @sql_connector.read_record( :orthogonal, [:eq, [:field, "id"], id_index])

        condition = [:or]
        ret.each{ |r| 
          r.delete("id")
          r.delete("run")
          andCond = [:and]
          @paramDefList.size.times{ |i|
            unassign_flag = true
            r.each{ |k, v|
              if @paramDefList[i].name == k
                parameter_array.push(@parameters[k][:correspond][v])
                andCond.push([:eq, [:field, k], @parameters[k][:correspond][v]])
                unassign_flag = false
                break
              end
            }
            if unassign_flag
              parameter_array.push(@paramDefList[i].get_n(not_allocate_indexes[i]))
              andCond.push([:eq, [:field, @paramDefList[i].name], @paramDefList[i].get_n(not_allocate_indexes[i])])
            end
          }
          condition.push(andCond)
        }        
        
        already = @sql_connector.read_record(:parameter, condition)

        if already.size != 0
          already.each{|ret|
            @run_id_queue[0][id_index].push(ret["parameter_id"])
          }
        else
          @run_id_queue[0][id_index].push(id)
        end
        @run_id_queue[0][id_index].uniq!

        return parameter_array
      end

      # 
      def get_available
        @available_numbers.length
      end

      # 
      def get_total
        @run_id_queue[0][:or_ids].size * @unassigned_total_size
      end

      #
      def get_v_index
        return @v_index
      end

      def get_runnable_size
        return @run_id_queue.size
      end

      def get_analysis_size
        return @f_test_queue.size
      end

      def get_generator_size
        return @generation_queue.size
      end

      #
      def do_variance_analysis
        return false if @f_test_queue.empty?
        debug("variance analysis: f-test queue: ") # p "variance analysis: f-test queue: "
        # debug("#{pp @f_test_queue.map{|q| q[:or_ids]}}") # pp @f_test_queue.map{|q| q[:or_ids]} 

        # analysis
        result_set = []
        count = 0
        parameter_keys = []

        @definitions.each { |k,v| parameter_keys.push(k) if v.kind_of?(Hash) && v["is_assigned"] }
        @f_test_queue[0][:or_ids].each{|oid|
          condition = "WHERE result_id IN ( " + @f_test_queue[0][oid].map{|i| "#{i}"}.join(", ") + ")"
          retval = @sql_connector.inner_join_record({base_type: :result, ref_type: :parameter,
                                              base_field: :result_id, ref_field: :parameter_id,
                                              condition: condition})
          if retval.length >= 0
            count += retval.length
            result_set.push(retval)
          end
        }
        return false if count < (@f_test_queue[0][:or_ids].size * @unassigned_total_size)
        debug("list length: #{@f_test_queue.size}, counter: #{@run_id_queue.size}")
        
        # variance analysis
        f_result = @f_test.run(result_set, parameter_keys, @sql_connector, @f_test_queue[0])
        @f_test_queue[0][:f_result] = f_result
        tested_sets = @f_test_queue.shift
        if @generation_queue.empty? || @generation_queue.find{|v| v[:or_ids].sort == tested_sets[:or_ids]}.nil?
          @generation_queue.push(tested_sets) #if !check_duplicate_f_test(tested_sets)
        end
        return true
      end

      # parameter set generation
      def do_parameter_generation
        return false if @generation_queue.empty?
        debug("parameter generation: generation queue")
        # debug("#{pp @generation_queue.map{|q| q[:or_ids]}}")
        
        # select index
        greedy = @prng.rand < @epsilon ? false : true #true
        index = greedy ? 0 : @prng.rand(@generation_queue.size)
        # @generation_queue.sort_by!{|v| -v[:priority]}
        @generation_queue.sort!{|a, b|
          amax, bmax = -1.0, -1.0
          a[:f_result].each{|k, v|
            if a[:search_params].include?(k)
              # amax = (v[:f_value] > amax) ? v[:f_value] : amax
              prior = log2(v[:f_value])#*v[:distance]
              prior = 0.0 if prior < 0.0
              if prior > amax
                amax = prior
              end
            end
          }
          b[:f_result].each{|k, v|
            if b[:search_params].include?(k)
              # bmax = (v[:f_value] > bmax) ? v[:f_value] : bmax
              prior = log2(v[:f_value])#*v[:distance]
              prior = 0.0 if prior < 0.0
              if prior > bmax
                bmax = prior
              end
            end
          }
          bmax <=> amax
        } if greedy

        # siginificant set is searched inside 
        condition = [:or]
        condition += @generation_queue[index][:or_ids].map{|i| [:eq, [:field, "id"], i]}
        orthogonal_rows = @sql_connector.read_record(:orthogonal, condition)
        # for debug
        debug_check_orthogonal(orthogonal_rows, @generation_queue[index])
        new_inside_list = generate_list_of_inside(orthogonal_rows, @generation_queue[index][:f_result])
        
        # outside
        new_outside_list = []
        if @generation_queue[index][:toward] == "outside"
          # p "generate outside parameter"
          if greedy
              name = greedy_selection(@generation_queue[index])
              @generation_queue[index][:search_params].delete(name.to_s)
              priority = log2(@generation_queue[index][:f_result][name.to_s][:f_value])#*@generation_queue[index][:f_result][name.to_s][:distance]
              priority = 0.0 if priority < 0.0
              new_outside_list = generate_list_of_outside(orthogonal_rows, name, priority, index)
          else
            if !generate_widely
              name = greedy_selection(@generation_queue[index])
              @generation_queue[index][:search_params].delete(name.to_s)
              priority = log2(@generation_queue[index][:f_result][name.to_s][:f_value])#*@generation_queue[index][:f_result][name.to_s][:distance]
              priority = 0.0 if priority < 0.0
              new_outside_list = generate_list_of_outside(orthogonal_rows, name, priority, index)
            end
          end
        end
        # if !new_outside_list.empty?
        #   pp new_outside_list
        #   # if new_outside_list[0][:param][:name] == "v2" && new_outside_list[0][:param][:paramDefs].include?(-0.3)
        #   #   pp new_outside_list
        #   #   exit(0)
        #   # end
        # end
        # extend_otableDB & parameter set store to queue
        if !new_inside_list.empty?
          next_sets = generate_next_search_area(@generation_queue[index][:or_ids], new_inside_list)
          next_sets.each{|set|
            if !set.empty?
              h = generate_id_data_list(set, "inside", @generation_queue[index][:priority], @parameters.keys)
              if 0 < h[:or_ids].uniq.size && h[:or_ids].uniq.size < 4
                error("debug: new inside list")
binding.pry                
                pp new_inside_list
                p "new param: #{pp new_param}"
                p "orthogonal"
                pp orthogonal_rows
                p "new area:"
                pp h
                exit(0)
              end
              @run_id_queue.push(h)
            end
          }
        end
        if !new_outside_list.empty?
          next_sets = generate_next_search_area(@generation_queue[index][:or_ids], new_outside_list)
          next_sets.each{|set|
            if !set.empty?
              h = generate_id_data_list(set, "outside", @generation_queue[index][:priority], @parameters.keys)
              if 0 < h[:or_ids].uniq.size && h[:or_ids].uniq.size < 4
                error("debug: new out list")
binding.pry                
                pp new_outside_list
                p "new param: #{pp new_param}"
                p "orthogonal"
                pp orthogonal_rows
                p "new area: "
                pp h
                exit(0)
              end
              @run_id_queue.push(h)
            end
          }
        end

        if @generation_queue[index][:toward] == "outside"
          if @generation_queue[index][:search_params].empty?
            @generation_queue.delete_at(index)
          # else
          #   @generation_queue.push(@generation_queue.shift)
          end
        else
          @generation_queue.delete_at(index)
        end

        @eop = true if @run_id_queue.empty? && @f_test_queue.empty? && @generation_queue.empty?
      end


      private

      # 
      def generate_id_data_list(id_list, toward=nil, priority=0.0, search_params=nil)
        h = {:or_ids => id_list}
        id_list.each{ |id| h[id] = [] }
        h[:toward] = toward
        h[:priority] = priority
        h[:search_params] = search_params.nil? ? [] : search_params
        return h
      end

      #
      def generate_widely
        id_set = DOEParameterGenerator.generate_wide(@sql_connector, @parameters, @definitions, @prng)
        h = generate_id_data_list(id_set, "outside", 1.0, @parameters.keys)

        if @generation_queue.empty? || @generation_queue.find{|v| v[:or_ids].sort == h[:or_ids]}.nil?
          if @f_test_queue.empty? ||  @f_test_queue.find{|test| test[:or_ids].sort == h[:or_ids].sort }.nil?
            if !check_duplicate_f_test(h)
              @run_id_queue.push(h)
              return true
            end
          end
        end
        return false
      end

      # 
      def greedy_selection(id_set)
        params = []
        selections = id_set[:f_result].select{|k,v| id_set[:search_params].include?(k.to_s)}
        name, max_fv = selections.max_by{ |k, v| v[:f_value] }
        selections.each{ |k, v|
          params.push(k) if max_fv[:f_value] == v[:f_value]
        }

        if 1 < params.size
          return params[@prng.rand(params.size)]
        else
          return params[0]
        end
      end

      # 
      def roulette_selection(f_result)
        sum = f_result.map{|k, v| v[:f_value]}.inject(:+)
        point = sum*@prng.rand
        needle = 0.0
        ret = nil
        f_result.each{|k, v|
          needle += v[:f_value]
          if point <= needle
            ret = k 
            break
          end
        }
        ret = f_result.last[0] if ret.nil?
        return ret
      end

      #
      def generate_list_of_inside(orthogonal_rows, f_result)
        new_inside_list = []
        @parameters.each{|k, v|
          if @f_test.check_significant(k, f_result)
            new_param, exist_ids = DOEParameterGenerator.generate_inside(
                                    @sql_connector, orthogonal_rows, @parameters,
                                    k, @definitions[k])
            if exist_ids.empty? && !new_param[:param][:paramDefs].empty?
              new_inside_list.push(new_param)
            elsif !exist_ids.empty?
              exist_ids.each{|set|
                chk_cond = [:eq, [:field, 'id_combination']]
                chk_cond.push(set.sort.to_s)
                if (@sql_connector.read_record(:f_test, chk_cond)).size == 0
                  priority = log2(f_result[k][:f_value])#*f_result[k][:distance]
                  priority = 0.0 if priority < 0.0
                  h = generate_id_data_list(set, "inside", priority, @parameters.keys)

                  if 0 <= h[:or_ids].uniq.size && h[:or_ids].uniq.size < 4
                    error("debug: existed inside")
binding.pry                    
                    p "exist area: #{exist_ids}"
                    p "new param:"
                    pp new_param
                    p "orthogonal"
                    pp orthogonal_rows
                    pp h
                    exit(0)
                  end
                  @run_id_queue.push(h)
                end
              }
            end
          end
        }

        return new_inside_list
      end

      #
      def generate_list_of_outside(orthogonal_rows, name, f_value, index=0)
        new_outside_list = []
        new_param, exist_ids = DOEParameterGenerator.generate_outside(
                                @sql_connector, orthogonal_rows, @parameters,
                                name, @definitions[name])
        if !new_param[:param][:paramDefs].empty?
          new_outside_list.push(new_param)
          # p "debug"
          # pp new_param[:param]
        end
        if !exist_ids.empty?
          exist_ids.each{ |set|
            chk_cond = [:eq, [:field, 'id_combination']]
            chk_cond.push(set.sort.to_s)
            if (@sql_connector.read_record(:f_test, chk_cond)).size == 0
              h = generate_id_data_list(set, "outside", f_value, @parameters.keys)
              if 0 <= h[:or_ids].uniq.size && h[:or_ids].uniq.size < 4
                error("debug existed outside")
binding.pry                
                p "exist area: #{exist_ids}"
                p "new param: #{pp new_param}"
                p "orthogonal"
                pp orthogonal_rows
                pp h
                exit(0)
              end
              @run_id_queue.push(h)
            end            
          }
        end
        return new_outside_list
      end

      # 
      def generate_next_search_area(old_rows, new_param_list)
        new_inside_area = []
        new_outside_area = []

        inside_list = []
        outside_list = []
        new_param_list.each{ |np| 
          if np[:case] == "inside"
            inside_list.push(np)
          else
            outside_list.push(np)
          end
        }

        if !inside_list.empty?
          extclm = extend_otableDB(old_rows, inside_list[0][:case], inside_list[0][:param])
          new_inside_area += OrthogonalTable.generate_area(@sql_connector, old_rows, inside_list[0], extclm)

          if 2 <= inside_list.size
            for i in 1...inside_list.size
              extclm = extend_otableDB(old_rows, inside_list[i][:case], inside_list[i][:param])
              tmp_area = []
              new_inside_area.each { |na|
                tmp_area += OrthogonalTable.generate_area(@sql_connector, na, inside_list[i], extclm)
              }
              new_inside_area = tmp_area
            end
          end
        end


        if !outside_list.empty?
          # condition = [:and]
          # condition += @parameters.map{|k, v|
          #   [:or,
          #     [:eq, [:field, k], v[:correspond].key(v[:paramDefs].max)], 
          #     [:eq, [:field, k], v[:correspond].key(v[:paramDefs].min)]
          #   ]
          # }

          # old_out_rows = @sql_connector.read_record(:orthogonal, condition)
          # old_out_ids = old_out_rows.map{|r| r["id"]}

          outside_list.each{|prm| # toriaezu
            extclm = extend_otableDB(old_rows, prm[:case], prm[:param])
            new_outside_area += OrthogonalTable.generate_area(@sql_connector,
                                  old_rows, prm, extclm)
          }
        
        #   outside_list.each{|prm|
        #     if !prm[:param][:paramDefs].nil?
        #       extclm = extend_otableDB(old_out_ids, prm[:case], prm[:param])
        #       tmp_area = []
        #       if new_outside_area.empty?
        #         tmp_area += OrthogonalTable.generate_area(
        #                       @sql_connector, old_out_ids, prm, extclm)
        #       else
        #         tmp_list = new_outside_area.map{|i| i}
        #         tmp_list.push(old_out_ids)
        #         tmp_list.each{|a|
        #           tmp_area += OrthogonalTable.generate_area(
        #                         @sql_connector, a, prm, extclm)
        #         }
        #       end
        #       new_outside_area += tmp_area
        #     else
        #       p "parameter array is nil"
        #     end
        #   }
        end

        return new_inside_area + new_outside_area
      end

      # 
      def check_duplicate_f_test(chk)
        condition = [:eq, [:field, 'id_combination']]
        condition.push(chk[:or_ids].sort.to_s)
        retval = @sql_connector.read_record(:f_test, condition)
        if retval.size > 0
          return true
        else
          return false
        end
      end

      #
      def extend_otableDB(or_ids, add_point_case, parameter)
        condition = [:or]
        condition += or_ids.map{|i| [:eq, [:field, "id"], i]}
        orthogonal_rows = @sql_connector.read_record(:orthogonal, condition)

        old_level = 0
        old_digit_num = 0
        ext_column = nil
        # binding.pry if (parameter[:paramDefs] - @parameters[parameter[:name]][:paramDefs]).empty?
        if orthogonal_rows.length == 0
          error("the no orthogonal array exist.")
          # binding.pry
          return -1
        end

        
        old_level = @parameters[parameter[:name]][:paramDefs].size #old_bits.length
        old_digit_num = orthogonal_rows[0][parameter[:name]].size
        digit_num = log2(old_level + parameter[:paramDefs].size).ceil

        condition = [:or]
        condition += @parameters[parameter[:name]][:correspond].map{|k,v| [:eq, [:field, parameter[:name]], k]}

        if old_digit_num < digit_num
          old_max_count = @sql_connector.read_max(:orthogonal, 'id', :integer)
          
          @extending = true # nen no tame
          update_parameter_correspond(parameter[:name], digit_num, old_digit_num, old_level)
          
          @sql_connector.copy_records(:orthogonal, nil)
          update_orthogonalDB(parameter[:name], "0", 1, old_max_count)
          new_max_count = @sql_connector.read_max(:orthogonal, 'id', :integer)
          update_orthogonalDB(parameter[:name], "1", old_max_count + 1, new_max_count)

          @extending = false
        end

        assign_parameter(add_point_case, parameter[:name], parameter[:paramDefs])
        
        return @parameters[parameter[:name]]
      end

      #
      def assign_parameter(add_point_case, name, add_parameters)
        # if add_parameters.size < 2 && add_point_case == "inside"
        #   @debugFlag = true
        # else
        #   @debugFlag = false
        # end
        # binding.pry if @debugFlag
        min_bit = nil
        h = {}
        case add_point_case
        when "outside(+)"
          right_digit_of_max = @parameters[name][:correspond].max_by(&:last)[0]
          if right_digit_of_max[-1] == "1" #[right_digit_of_max.size-1]
            add_parameters.sort!
          else
            add_parameters.reverse!
          end
        when "outside(-)"
          right_digit_of_min = @parameters[name][:correspond].min_by(&:last)[0]
          if right_digit_of_min[right_digit_of_min.size-1] == "0"
            add_parameters.sort!
          else
            add_parameters.reverse!
          end
        when "inside"
          digit_num_of_minus_side = @parameters[name][:correspond].select{|k,v|
              v < add_parameters.min
            }.max_by{|_, v| v}
          digit_num_of_minus_side = digit_num_of_minus_side[0]  
          if digit_num_of_minus_side[-1] == "0"#digit_num_of_minus_side[digit_num_of_minus_side.size-1] == "0"
            count = 1
            add_parameters.each{|v| 
              h[v] = (count % 2).to_s
              count += 1
            }
          else
            count = 0
            add_parameters.each{|v| 
              h[v] = (count % 2).to_s
              count += 1
            }
          end
        when "both side"
          if add_parameters.size == 2
            # right_digit_of_max = @parameters[name][:correspond].max_by(&:last)[0]
            right_digit = @parameters[name][:correspond].max_by { |item| 
              item[1] < add_parameters.max ? item[1] : -1 
            }[0]
            left_digit = @parameters[name][:correspond].min_by { |item| 
              item[1] > add_parameters.min ? item[1] : @parameters[name][:correspond].size
            }[0]
            if right_digit[-1] == "0" # [right_digit.size-1]
              # add_parameters.reverse!
              h[add_parameters.max] = "1"
            else
              # add_parameters.sort!
              h[add_parameters.max] = "0"
            end
            if left_digit[-1] == "0" # [right_digit.size-1]
              # add_parameters.reverse!
              h[add_parameters.min] = "1"
            else
              # add_parameters.sort!
              h[add_parameters.min] = "0"
            end
          else
            if @parameters[name][:paramDefs].max < add_parameters[0] #upper
              right_digit_of_max = @parameters[name][:correspond].max_by(&:last)[0]
              if right_digit_of_max[-1] == "0" #[right_digit_of_max.size - 1]
                h[add_parameters[0]] = "1"
              else
                h[add_parameters[0]] = "0"
              end
            elsif @parameters[name][:paramDefs].min > add_parameters[0] #lower
              right_digit_of_min = @parameters[name][:correspond].min_by(&:last)[0]
              if right_digit_of_min[-1] == "0" # [right_digit_of_min.size - 1]
                h[add_parameters[0]] = "1"
              else
                h[add_parameters[0]] = "0"
              end
            else#med => error
              error("parameter creation is error")
              # binding.pry
              p add_parameters
              pp @parameters[name]
              exit(0)
            end
          end
        else
          error("new parameter could not be assigned to bit on orthogonal table")
        end
        old_level = @parameters[name][:paramDefs].size
        @parameters[name][:paramDefs] += add_parameters
        link_parameter(name, h)
        # binding.pry if @debugFlag
        @parameters[name]
      end

      #
      def update_parameter_correspond(param_name, digit_num, old_digit_num, old_level)
        old_bit_str = "%0"+old_digit_num.to_s+"b"
        new_bit_str = "%0"+digit_num.to_s+"b"
        # for i in 0...old_level
        for i in 0...(2**old_digit_num)
          if @parameters[param_name][:correspond].key?(old_bit_str%i)
            @parameters[param_name][:correspond][(new_bit_str%i)] = @parameters[param_name][:correspond][(old_bit_str%i)]
            @parameters[param_name][:correspond].delete(old_bit_str%i)
          end
        end
      end

      # 
      def link_parameter(name, paramDefs_hash)
        # binding.pry if @debugFlag
        digit_num = log2(@parameters[name][:paramDefs].size).ceil
        old_level = @parameters[name][:paramDefs].size - paramDefs_hash.size
        top = @parameters[name][:paramDefs].size
        bit_i = 0
        while bit_i < top
          bit = ("%0" + digit_num.to_s + "b") % bit_i
          if !@parameters[name][:correspond].key?(bit)
            if paramDefs_hash.has_value?(bit[-1]) #(bit[bit.size-1])
              param = paramDefs_hash.key(bit[-1]) #(bit[bit.size-1])
              @parameters[name][:correspond][bit] = param
              paramDefs_hash.delete(param)
            else
              top += 1
              debug("#{paramDefs_hash}, top_count: #{top}")
              debug("bit:#{bit}, last_str:#{bit[-1]}")
              # debug("#{pp @parameters[name]}")
              # exit(0) if top > 100
            end 
          end
          bit_i += 1
        end
        if @parameters[name][:paramDefs].size != @parameters[name][:correspond].size
          error("no assignment parameter: 
            defs_L:#{@parameters[name][:paramDefs].size}, 
            corr_L:#{@parameters[name][:correspond].size}")
          # binding.pry
          pp paramDefs_hash
          pp @parameters[name]
          exit(0)
        end
      end

      # upload initial table
      def upload_initial_orthogonal_db(table=nil)
        error("uploading data for MySQL is empty") if table.nil?
        return if @sql_connector.read_record(:orthogonal, [:eq, [:field, "id"], 1]).length > 0
        msgs = []
        (0...table[0].size).each{|row|
          msg = {:id => row+1, :run => 0}
          @parameters.each{|name, param|
            msg[name.to_sym] = table[param[:column_id]][row]
          }
          msgs.push(msg)
        }
        upload_orthogonal_table_db(msgs)
      end

      # 
      def update_orthogonalDB(pname, bit_str, strt_id, end_id)
        condition = "#{pname} = CONCAT('#{bit_str}', #{pname}) WHERE id BETWEEN #{strt_id} AND #{end_id}"
        @sql_connector.update_string(:orthogonal, condition)
      end

      # upload additional tables
      def upload_orthogonal_table_db(msgs=nil)
        error("uploading data for MySQL is empty") if msgs.nil?
        
        msgs.each{|msg|
          id = msg[:id].to_i
          if (retval = @sql_connector.insert_record(
            :orthogonal, msg).length != 0)
            error("fail to insert new orthogonal table. #{retval}")
            return -2
          end
        }
        
        return 0
      end

      # update exisiting table
      def update_orthogonal_table_db(msgs=nil)
        msgs.uniq.each{|msg|
          msg.each{|name, vh|
            @sql_connector.update_record( :orthogonal, {name => vh[:new]}, 
                                          [:eq, [:field, name.to_s], vh[:old]])
          }
        }
      end

      #
      def unassigned_value_to_indexes(v)
        indexes = []
        k = v
        divider = @unassigned_total_size
        @total_indexes.each_with_index{ |n, i|
          if @definitions[@paramDefList[i].name]["is_assigned"]
            indexes.push(0)
          else
            divider = (divider / n).to_i
            l = (k / divider).to_i
            k -= l * divider
            indexes.push(l)  
          end
        }
        return indexes
      end

      # toy_problem
      def debug_check_orthogonal(rows, popout)
        v1 = []
        v2 = []
        params = {"v1" => [], "v2" => []}
        rows.each{|row|
          v1.push(row["v1"][-1]) #[row["v1"].size - 1]
          v2.push(row["v2"][-1]) #[row["v2"].size - 1]
          params["v1"].push(@parameters["v1"][:correspond][row["v1"]])
          params["v2"].push(@parameters["v2"][:correspond][row["v2"]])
        }
        v1.uniq!
        v2.uniq!
        params["v1"].uniq!
        params["v2"].uniq!

        if v1.size != 2 || v2.size != 2
          error("")
          # binding.pry
          pp rows
          pp params
          @parameters.each{|k,v|
            p k
            p v[:paramDefs].sort
            pp v[:correspond].sort
          }
          pp popout
          exit(0)
        end
      end
    end
  end
end
