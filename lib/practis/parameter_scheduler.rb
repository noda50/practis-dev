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
        # (2013/09/12) written by matsushima ==================
        pp assign_list
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
      include Math

      attr_reader :current_indexes
      attr_reader :total_indexes
      attr_reader :paramDefList

      #
      def initialize(paramDefs)
        @paramDefList = chk_arg(Array, paramDefs)
        @f_test=FTest.new
      end

      # 
      def init_doe(sql_connector, table, assign_list)
        @sql_connector = sql_connector
        @assign_list = assign_list
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
          if @assign_list[paramDef.name]
            @parameters[paramDef.name] = {column_id: i, correspond: {}, paramDefs: paramDef.values.sort}
            # parameters.push({ :name => paramDef.name, :paramDefs => paramDef.values})
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
        @unassigned_total.collect{|t| @unassigned_total_size *= t}
        @total_number = get_total   
        @available_numbers = get_total.times.map { |i| i } 
      end
      
      #
      def get_paramValues(id=nil)
        if @available_numbers.length <= 0
          debug("no available parameter, \n" +
                "total index num: #{@total_indexes.length}, \n" +
                "total indexes: #{@total_indexes}, \n" +
                "available: #{@available_numbers.length}, \n" +
                "allocated: #{@allocated_num} \n")
          return nil if !set_next_list
        end

        v = @available_numbers.shift
        @v_index = v / @unassigned_total_size
        @allocated_num += 1
        not_allocate_indexes = unassigned_value_to_indexes(v % @unassigned_total_size)
        parameter_array = []

        id_index = @id_list_queue[@current_qcounter][:or_ids][@v_index]
        @id_list_queue[@current_qcounter][id_index].push(id)
        ret = @sql_connector.read_record( :orthogonal, [:eq, [:field, "id"], id_index])

        
        ret.each{|r| 
          r.delete("id")
          r.delete("run")

          @paramDefList.size.times{ |i|
            unassign_flag = true
            r.each{ |k, v|
              if @paramDefList[i].name == k
                parameter_array.push(@parameters[k][:correspond][v])
                unassign_flag = false
                break
              end
            }
            if unassign_flag
              parameter_array.push(@paramDefList[i].get_n(not_allocate_indexes[i]))
            end
          }
        }
        return parameter_array
      end

      # 
      def get_available
        if @available_numbers.length <= 0
          result_set = []
          count = 0
          parameter_keys = []
          @assign_list.each { |k,v| parameter_keys.push(k) if v }
          @id_list_queue[0][:or_ids].each{|oid|
            condition = [:or] + @id_list_queue[0][oid].map { |i|  [:eq, [:field, "result_id"], i]}
            pp retval = @sql_connector.inner_join_record({base_type: :result, ref_type: :parameter,
                                                base_field: :result_id, ref_field: :parameter_id,
                                                condition: condition})
            if retval.length >= 0
              count += retval.length
              result_set.push(retval)
            end
          }

          return 1 if count < (@id_list_queue[0][:or_ids].size * @unassigned_total_size)

          # variance analysis
          @f_test.run(result_set, parameter_keys)

          # parameter set generation
          orthogonal_rows = []
          @id_list_queue[@current_qcounter][:or_ids].each{|id|
            ret = @sql_connector.read_record( :orthogonal, [:eq, [:field, "id"], id])
            orthogonal_rows.push(ret) if ret.length > 0
          }
          
          generate_inside(orthogonal_rows, @parameters["Noise"])
exit(0)
          # extend_otableDB
          # parameter set store to queue 

        end

        @available_numbers.length
      end

      # 
      def get_total
        @id_list_queue[@current_qcounter][:or_ids].size * @unassigned_total_size
      end

      def get_v_index
        return @v_index
      end
            

      private

      #
      def extend_otableDB(area, add_point_case, parameter)
        old_level = 0
        old_digit_num = 0
        twice = false
        ext_column = nil

        condition = [:or] + area.map{|i| [:eq, [:field, "id"], i]}
        retval = @sql_connector.read_record(:orthogonal, condition)
        if retval.length == 0
          error("the no orthogonal array exist.")
          return -1
        end

        oldlevel = @sql_connector.read_distinct_record(:orthogonal, "#{parameter[:name]}" ).length
        old_digit_num = retval[0][parameter[:name]].size#oldlevel / 2
        
        if old_digit_num < (sqrt(oldlevel+parameter[:paramDefs].size).ceil)
          update_msgs = []
          upload_msgs = []

          retval.each{|ret|
            upd_h = {id: ret["id"]}
            upl_h = {id: ret["id"] + retval.length} # ??? abunai kamo
            ret.each{|k,v|
              if k != "id"
                if k == parameter[:name] 
                  upd_h[k.to_sym] = "0" + v
                  upl_h[k.to_sym] = "1" + v
                else
                  upd_h[k.to_sym] = v
                  upl_h[k.to_sym] = v
                end
              end
            }
            update_msgs.push(upd_h)
            upload_msgs.push(upl_h)
          }

          update_orthogonal_table_db(update_msgs)
          upload_orthogonal_table_db(upload_msgs)
        end

        return parameter
      end

      # set next list of parameter combinations set 
      def set_next_list
        if @current_qcounter + 1 < @id_list_queue.size
          @current_qcounter += 1
          @available_numbers = get_total.times.map { |i| i }
          return true
        else
          return false
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
        msgs.each{|msg|
          id = msg[:id].to_i
          
          if (retval = 
              @sql_connector.read_record(:orthogonal, [:eq, [:field, "id"], id])).length != 0
            # update
            flag = false
            upld = {}
            retval.each{|ret|
              ret.each{|k, v|    
                if msg[k.to_sym] != v
                  upld[k.to_sym] = msg[k.to_sym]
                  flag = true
                end
              }
            }
            if flag
              nret = @sql_connector.update_record(:orthogonal, upld, [:eq, [:field, "id"], id])
              debug("#{pp nret}")
            end          
          end
        }
      end

      #
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
  end
end
