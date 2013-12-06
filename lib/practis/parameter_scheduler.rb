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
        # pp @assign_list
        # p "divider: #{divider}, total indexes: #{@total_indexes}"
        @total_indexes.each_with_index{ |n, i|
          if @assign_list[@paramDefList[i].name]
            indexes.push(0)
          else
            # p "name: #{@paramDefList[i].name}, divider: #{divider}, i: #{i}"
            divider = (divider / n).to_i
            l = (k / divider).to_i
            k -= l * divider
            indexes.push(l)  
          end
        }
        return indexes
      end
    end

    # 
    class DOEScheduler
      include Practis
      include DOEParameterGenerator
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
      end

      # 
      def init_doe(sql_connector, table, doe_definitions)
        @sql_connector = sql_connector
        @definitions = doe_definitions
        @id_list_queue = []
        @current_qcounter = 0
        

        h = {:or_ids => []}
        table[0].size.times.each{|r| 
          h[:or_ids].push(r)
          h[r] = []
        }
        @id_list_queue.push(h)


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
          return nil if !set_next_list
        end

        return nil if @extending

        if @available_numbers.size == 0
          pp @id_list_queue
          p @current_qcounter
          pp @id_list_queue[@current_qcounter]
        end
        
        v = @available_numbers.shift
        @v_index = v / @unassigned_total_size # debug error
        @allocated_num += 1
        not_allocate_indexes = unassigned_value_to_indexes(v % @unassigned_total_size)
        parameter_array = []

        id_index = @id_list_queue[@current_qcounter][:or_ids][@v_index]
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
        
        # pp condition # debug error
        already = @sql_connector.read_record(:parameter, condition)

        if already.size != 0
          already.each{|ret|
            @id_list_queue[@current_qcounter][id_index].push(ret["parameter_id"])
          }
        else
          @id_list_queue[@current_qcounter][id_index].push(id)
        end
        @id_list_queue[@current_qcounter][id_index].uniq!

        return parameter_array
      end

      # 
      def get_available
        @available_numbers.length
      end

      # 
      def get_total
        @id_list_queue[@current_qcounter][:or_ids].size * @unassigned_total_size
      end

      #
      def get_v_index
        return @v_index
      end

      #
      def do_variance_analysis
        # analysis
        result_set = []
        count = 0
        parameter_keys = []
        new_param_list = []
        @definitions.each { |k,v| parameter_keys.push(k) if v["is_assigned"] }
        @id_list_queue[0][:or_ids].each{|oid|
          condition = [:or] + @id_list_queue[0][oid].map { |i|  [:eq, [:field, "result_id"], i]}
          retval = @sql_connector.inner_join_record({base_type: :result, ref_type: :parameter,
                                              base_field: :result_id, ref_field: :parameter_id,
                                              condition: condition})
          if retval.length >= 0
            count += retval.length
            result_set.push(retval)
          end
        }
        return false if count < (@id_list_queue[0][:or_ids].size * @unassigned_total_size)

        p "list size: #{@id_list_queue.size}"
        p "counter: #{@current_qcounter}"
        pp @id_list_queue[0]
        

        # variance analysis
        f_result = @f_test.run(result_set, parameter_keys, @sql_connector)

        # parameter set generation
        condition = [:or]
        condition += @id_list_queue[0][:or_ids].map{|i| [:eq, [:field, "id"], i]}
        orthogonal_rows = @sql_connector.read_record(:orthogonal, condition)
        
        bothside_flag = true
        outside_plus_flag = true
        outside_minus_flag = true
        # = = = hard coding = = = 
        @parameters.each{|k, v|
          if @f_test.check_significant(k, f_result) # inside
            new_param, exist_ids = generate_inside(@sql_connector, orthogonal_rows, 
                                                  @parameters, k, @definitions[k])
            if exist_ids.empty? && !new_param[:param][:paramDefs].nil? # !new_param[:param][:paramDefs].empty?
              new_param_list.push(new_param)
            elsif !exist_ids.empty?
              exist_ids.each{|a|
                h = {:or_ids => a}
                a.each{|i|
                  h[i] = []
                }
                @id_list_queue.push(h)
              }
            end
          end
          params = orthogonal_rows.map {|r| @parameters[k][:correspond][r[k]] }
          bothside_flag = bothside_flag && (params.include?(@parameters[k][:paramDefs].max) || params.include?(@parameters[k][:paramDefs].min))
          outside_plus_flag = outside_plus_flag && params.include?(@parameters[k][:paramDefs].max)
          outside_minus_flag = outside_minus_flag && params.include?(@parameters[k][:paramDefs].min)
        }

        p "do both side: #{bothside_flag}"
        p "do out side(+): #{outside_plus_flag}"
        p "do out side(-): #{outside_minus_flag}"
        # out side
        if bothside_flag
          # new_param, exist_ids = generate_outside(@sql_connector, orthogonal_rows, 
          #                                       @parameters, k, @definitions[k])
        end
        # = = = (end) hard coding = = = 


        # extend_otableDB & parameter set store to queue
        if !new_param_list.empty?
          next_sets = generate_next_search_area(@id_list_queue[0][:or_ids], new_param_list)
          next_sets.each{|set|
            if !set.empty?
              h = {:or_ids => []}
              set.each{|r| 
                h[:or_ids].push(r)
                h[r] = []
              }
              @id_list_queue.push(h)
            end
          }
        end

        @id_list_queue.shift

        if !@id_list_queue.empty?
          @current_qcounter -= 1 if @current_qcounter > 0
          @available_numbers = get_total.times.map { |i| i }
        else
          @eop = true
        end

        return true
      end


      private

      # set next list of parameter combinations set 
      def set_next_list
        if @current_qcounter < @id_list_queue.size - 1
          @current_qcounter += 1
          @available_numbers = get_total.times.map { |i| i }
          return true
        else
          return false
        end
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
          new_inside_area += generate_area(@sql_connector, old_rows, inside_list[0], extclm)

          if 2 <= inside_list.size
            for i in 1...inside_list.size
              extclm = extend_otableDB(old_rows, inside_list[i][:case], inside_list[i][:param])
              tmp_area = []
              new_inside_area.each { |na|
                tmp_area += generate_area(@sql_connector, na, inside_list[i], extclm)
              }
              new_inside_area = tmp_area
            end
          end
        end

        if !outside_list.empty?
          extclm = extend_otableDB(old_rows, outside_list[0][:case], outside_list[0][:param])
          new_outside_area += generate_area(@sql_connector, old_rows, outside_list[0], extclm)

          if 2 <= outside_list.size
            for i in 1...outside_list.size
              extclm = extend_otableDB(old_rows, outside_list[i][:case], outside_list[i][:param])
              tmp_area = []
              new_outside_area.each { |na|
                tmp_area += generate_area(@sql_connector, na, outside_list[i], extclm)
              }
              new_outside_area = tmp_area
            end
          end
        end

        return new_inside_area + new_outside_area
      end

      #
      def extend_otableDB(or_ids, add_point_case, parameter)
        condition = [:or]
        condition += or_ids.map{|i| [:eq, [:field, "id"], i]}
        orthogonal_rows = @sql_connector.read_record(:orthogonal, condition)

        old_level = 0
        old_digit_num = 0
        twice = false
        ext_column = nil

        if orthogonal_rows.length == 0
          error("the no orthogonal array exist.")
          return -1
        end

        old_level = @parameters[parameter[:name]][:paramDefs].size #old_bits.length
        old_digit_num = orthogonal_rows[0][parameter[:name]].size
        digit_num = sqrt(old_level + parameter[:paramDefs].size).ceil

        condition = [:or]
        condition += @parameters[parameter[:name]][:correspond].map{|k,v| [:eq, [:field, parameter[:name]], k]}
        orthogonal_rows = @sql_connector.read_record(:orthogonal, condition)

        if old_digit_num < digit_num
          max_count = @sql_connector.read_max(:orthogonal, 'id', :integer)
          row_ids = orthogonal_rows.map{|r| r["id"] + max_count }
          @extending = true
          update_parameter_correspond(parameter[:name], digit_num, old_digit_num, old_level)
          update_msgs = []
          upload_msgs = []

          upload_msgs = (max_count...(2*max_count)).inject([]){|arr, i|
            arr << {id: i} if !row_ids.include?(i)
            arr
          }


          orthogonal_rows.each{|ret|
            old_value_msg = {}
            upl_h = {id: ret["id"] + max_count}
            ret.each{|k, v|
              if k != "id" # TODO: reducing after bugfix
                if k == parameter[:name]
                  p "#{k} old: #{v} new:#{"0"+v}"
                  old_value_msg[k.to_sym] = {old: v, new: "0" + v}
                  ret[parameter[:name]] = "0" + v
                  upl_h[k.to_sym] = "1" + v
                else
                  upl_h[k.to_sym] = v
                end
              end
            }
            update_msgs.push(old_value_msg)
            upload_msgs.push(upl_h)
          }
          
          update_orthogonal_table_db(update_msgs)
          upload_orthogonal_table_db(upload_msgs)
          @extending = false
        end

        assign_parameter(old_level, add_point_case, parameter[:name], parameter[:paramDefs])
        
        return @parameters[parameter[:name]]
      end

      #
      def assign_parameter(old_level, add_point_case, name, add_parameters)
        case add_point_case
        when "outside(+)"
          right_digit_of_max = @parameters[name][:correspond].max_by(&:last)[0]
          if right_digit_of_max[right_digit_of_max.size - 1] == "1"
            add_parameters.sort!
          else
            add_parameters.reverse!
          end
        when "outside(-)"
          right_digit_of_min = @parameters[name][:correspond].min_by(&:last)[0]
          if right_digit_of_min[right_digit_of_min.size - 1] == "0"
            add_parameters.sort!
          else
            add_parameters.reverse!
          end
        when "inside"
          digit_num_of_left_point = @parameters[name][:correspond].max_by { |item| (item[1] < add_parameters[0]) ? item[1] : -1}[0]
          if digit_num_of_left_point[digit_num_of_left_point.size - 1] == "0"
            add_parameters.reverse!
          else
            add_parameters.sort!
          end
        when "both side"
          right_digit_of_max = @parameters[name][:correspond].max_by(&:last)[0]
          if right_digit_of_max[right_digit_of_max.size - 1] == "1"
            add_parameters.reverse!
          else
            add_parameters.sort!
          end
        else
          error("new parameter could not be assigned to bit on orthogonal table")
        end
        @parameters[name][:paramDefs] += add_parameters
        link_parameter(name, add_parameters)
        @parameters[name]
      end

      #
      def update_parameter_correspond(param_name, digit_num, old_digit_num, old_level)
        old_bit_str = "%0" + old_digit_num.to_s + "b"
        new_bit_str = "%0" + digit_num.to_s + "b"
        for i in 0...old_level
          @parameters[param_name][:correspond][new_bit_str % i] = @parameters[param_name][:correspond][old_bit_str % i]
          @parameters[param_name][:correspond].delete(old_bit_str % i)
        end
      end

      # 
      def link_parameter(name, add_paramDefs)
        digit_num = sqrt(@parameters[name][:paramDefs].size).ceil
        old_level = @parameters[name][:paramDefs].size - add_paramDefs.size

        for i in old_level...@parameters[name][:paramDefs].size do
          bit = ("%0" + digit_num.to_s + "b") % i
          if !@parameters[name][:correspond].key?(bit)
            @parameters[name][:correspond][bit] = @parameters[name][:paramDefs][i]
          end
        end
      end

      # upload initial table
      def upload_initial_orthogonal_db(table=nil)
        error("uploading data for MySQL is empty") if table.nil?
        
        msgs = []
        (0...table[0].size).each{|row|
          msg = {:id => row, :run => 0}
          @parameters.each{|name, param|
            msg[name.to_sym] = table[param[:column_id]][row]
          }
          msgs.push(msg)
        }
        upload_orthogonal_table_db(msgs)
      end

      # upload additional tables
      def upload_orthogonal_table_db(msgs=nil)
        error("uploading data for MySQL is empty") if msgs.nil?
        
        msgs.each{|msg|
          id = msg[:id].to_i
          if (retval =  
              @sql_connector.read_record(:orthogonal, [:eq, [:field, "id"], id])).length == 0
            if (retval = @sql_connector.insert_record(
              :orthogonal, msg).length != 0)
              error("fail to insert new orthogonal table. #{retval}")
              return -2
            end
          end  
        }
        
        return 0
      end

      # update exisiting table
      def update_orthogonal_table_db(msgs=nil)

        pp msgs
        msgs.each{|msg|
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
    end
  end
end
