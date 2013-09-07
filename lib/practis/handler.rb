#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'socket'

require 'practis'
require 'practis/message'
require 'practis/net'

module Practis
  module Net
    module Handler

      include Message

      #=== Abstract class for common handler.
      #
      #Store the connected socket and the name of the handler, be called from
      #Daemon.
      class CommonHandler < Thread

        include Message
        include Net
        include Practis

        attr_accessor :sock, :running, :name, :parent

        @name = nil

        #=== Initialize method.
        #
        #Simpley run thread.
        #
        #parent :: Reference to a parent daemon.
        #sock :: Connected socket.
        #timeout :: Timeout seconds of IO::select.
        def initialize(parent, sock, timeout=1)
          debug("init handler")
          @parent = parent
          @sock = sock
          @timeout = timeout
          @running = true
          super(&method(:thread))
        end

        protected
        def finish
          @running = false
        end

        def terminate
          close_sock(@sock)
          @running = false
        end

        private
        #=== Message handle thread.
        #
        #Using IO::select, parses the received JSON message, call the handler.
        def thread
          debug("#{self.class.name} handler run thread")
          while true
            debug("#{self.class.name} check msg")
            unless @running
              debug("#{self.class.name} not running")
              break
            end
            debug("#{self.class.name} try to recv")
            unless (data = precv(@sock)).kind_of?(Hash)
              error("fail to receive. errno:#{data}")
              caller().each{|c| error("... called from:" + c.to_s)}
              finish
              return
            end
            handle(@sock, data)
          end
        end

        #=== Abstract method
        #
        #The method has to be overrided in implemented class.
        #
        #parsed_message :: Parsed message with hash type.
        def handle(socket, parsed_message)
        end
      end

      public
      #=== Handle JoinPractis messages.
      #
      #When MessageHandler receives a JoinPractis message, this handler is
      #called.
      #
      class JoinPractisHandler < CommonHandler

        #=== Override CommonHandler.handle
        #
        #Proceed JoinPractis flow. The handler receives the request from 
        #daemons, registers them into practis and replies the settings of 
        #practis. Then the handler registers the access permissions for the 
        #databases with the id of the request daemons. When the keepalive
        #duration is expired, these permissions are also expired.
        #
        def handle(socket, parsed_message)
          debug("start #{self.class.name}")
          if parsed_message.nil?
            warn("JoinPractisHandler handle parse nil")
            terminate
            return
          end
          debug(parsed_message)
          partial_tree = @parent.allocate_node(parsed_message[:node_type],
                                               parsed_message[:addr], nil,
                                               parsed_message[:parallel])
          debug("#{self.class.name} partial tree #{partial_tree.to_json}")
          debug("#{self.class.name} keep alive #{@parent.keepalive_duration}")
          # Create AckSendSetting message.
          id = -1
          id = partial_tree.mynode[:id] unless partial_tree.nil?
          if (retval = psend(socket,
              create_message(MSG_TYPE_ASS, @parent.mynode.id, id,
                             partial_tree.to_json, @parent.keepalive_duration,
                             @parent.executable_command,
                             @parent.executable_path,
                             #@parent.result_accessor))) < 0
                             @parent.result_fields))) < 0
            error("fail to send AckSendSetting. errno: #{retval}")
            finish
            return
          end
          debug("#{self.class.name} recieve AckRecvSetting")
          # Recieve AckRecvSetting
          unless (data = precv(socket)).kind_of?(Hash)
            error("fail to receive AckRecvSetting. errno: #{data}")
            finish
            return
          end
          debug("#{self.class.name} recv: #{data}")
          if data.nil?
            error("#{self.class.name}: AckRecvSetting message is invalid")
          elsif data[:status] == MSG_STATUS_OK
            debug("#{self.class.name} succeed JoinPractis process")
          else
            debug("#{self.class.name} failed JoinPractis process")
          end
          # Finish the thread.
          finish
        end
      end

      class LeavePractisHandler < CommonHandler
      end

      #=== Handle the executable binaries request from other daemons.
      class ReqExecutableHandler < CommonHandler

        def handle(socket, parsed_message)
          debug("start #{self.class.name}")
          if parsed_message.nil?
            terminate
            return
          end
          # check the result
          executables = []
=begin
          count = 1
          while !(executable = @parent.config.read(
              "executable_transfer#{count}")).nil?
            begin
              unless File.exist?(executable)
                error("specified executable does not exist. #{executable}")
                count += 1
                next
              end
              executable_name = File::basename(executable)
              # check existing columns
              obj = (f = File.open(executable, "rb")).read
              f.close
              str = str[0] \
                if (str = obj.unpack(CONVERT_FORMAT)).class.name == "Array"
              executables.push({:executable_name => executable_name,
                                :executable_binary => str})
            rescue Exception => e
              error("fail to load executable. #{e.message}")
              error(e.backtrace)
              raise e
            end
            count += 1
          end
=end
          @parent.config.read("executable_transfer").each do |ex|
            begin
              unless File.exist?(ex)
                error("specified executable does not exist. #{ex}")
                next
              end
              executable_path = File::dirname(ex)
              executable_name = File::basename(ex)
              if File.directory?(ex)
                executable_name = "#{executable_name}.zip"
                #debug("create zip archive, input: #{ex}, output: #{executable_name}")
                if zip_archive(ex, executable_name, true) < 0
                  error("fail to zip the directory #{path.inspect}")
                  next
                end
              end
              # check existing columns
              obj = (f = File.open(File.join(executable_path, executable_name), "rb")).read
              f.close
              str = str[0] \
                if (str = obj.unpack(CONVERT_FORMAT)).class.name == "Array"
              executables.push({:executable_name => executable_name,
                                :executable_binary => str})
            rescue Exception => e
              error("fail to load executable. #{e.message}")
              error(e.backtrace)
              raise e
            end
          end
          if (retval = psend(socket,
              create_message(MSG_TYPE_ASE, parsed_message[:src_id],
                             @parent.mynode.id, executables))) < 0
            error("fail to send AckKeepAlive. errno:#{retval}")
            finish
            return
          end
          finish
        end
      end

      class ReqParametersHandler < CommonHandler

        def handle(socket, parsed_message)
          debug("start #{self.class.name}")
          if parsed_message.nil?
            warn("ReqParametersHandler handle parse nil")
            terminate
            return
          end
          debug("#{self.class.name}:  requested parameters " +
                "#{parsed_message[:request_number]}, " +
                " from #{parsed_message[:src_id]}")
          # Allocate parameters in JSON
          parameters = @parent.allocate_parameters(
            parsed_message[:request_number].to_i, parsed_message[:src_id].to_i)
          if parameters.length > 0
            info("#{self.class.name}: allocated parameters #{parameters}")
          else
            info("#{self.class.name}: currently no available parameter.")
          end
          # Create AckSendParameters message.
          debug("#{self.class.name}: send AckSendParameters message to " +
                "#{parsed_message[:src_id]}")
          if (retval = psend(socket,
              create_message(MSG_TYPE_ASP, parsed_message[:src_id].to_i,
                             @parent.mynode.id, parameters))) < 0
            error("fail to send AckSendParameters. errno:#{retval}")
            finish
            return
          end
          # Recieve AckRecvParameters
          unless (data = precv(socket)).kind_of?(Hash)
            error("fail to receive AckRecvParameters. errno: #{data}")
            finish
            return
          end
          if data[:status] == MSG_STATUS_OK
            debug("#{self.class.name}: succeed ReqParameters process.")
            parameters.each { |parameter|
              @parent.parameter_pool.length.times { |i|
                (@parent.parameter_pool[i].state = PARAMETER_STATE_EXECUTING;
                 break) if @parent.parameter_pool[i].uid == parameter.uid } }
          else
            warn("#{self.class.name}: failed ReqParameters process")
            parameters.each { |parameter|
              @parent.parameter_pool.length.times { |i|
                (@parent.parameter_pool[i].state = PARAMETER_STATE_READY;
                 break) if @parent.parameter_pool[i].uid == parameter.uid } }
          end
          # Finish the thread.
          finish
        end
      end

      class UpdateSettingHandler < CommonHandler
      end

      class AbortExecutionHandler < CommonHandler
      end

      class RestartExecutionHandler < CommonHandler
      end

      class UploadResultHandler < CommonHandler

        def handle(socket, parsed_message)
          debug("start #{self.class.name}")
          (terminate; return) if parsed_message.nil?
          # check the result
          if (retval = @parent.upload_result(parsed_message)) < 0
            error("fail to upload result. errno: #{retval}")
          end
          finish
        end
      end

      class StartExecutionHandler < CommonHandler

        def handle(socket, parsed_message)
          debug("start #{self.class.name}")
          (terminate; return) if parsed_message.nil?
          # check the result
          executor_id = parsed_message[:executor_id]
          parameter_id = parsed_message[:result_id]
          #update the state and time
          if @parent.update_started_parameter_state(
              parameter_id, executor_id) < 0
            error("fail to update started parameter.")
          end
        end
      end

      class KeepAliveHandler < CommonHandler

        #=== handle method implementation.
        def handle(socket, parsed_message)
          debug("start #{self.class.name}")
          (terminate; return) if parsed_message.nil?
          node_id = parsed_message[:src_id].to_i
          queueing = parsed_message[:queueing].to_i
          executing = parsed_message[:executing].to_i
          debug("KeppAlive: id #{node_id}, queueing: #{queueing}, executing: " +
                "#{executing}")
          @parent.cluster_tree.update(:id, node_id, :queueing, queueing)
          @parent.cluster_tree.update(:id, node_id, :executing, executing)
          @parent.cluster_tree.update(:id, node_id, :keepalive,
                                      @parent.keepalive_expired_duration)
          # update node database
          if (retval = @parent.update_node_state(node_id, queueing,
                                                 executing)) < 0
            error("fail to update the node state. errno: #{retval}")
          end
          # Create AckKeepAlive message.
          debug("KeppAlive: create reply message #{@parent.mynode.id}")
          if (retval = psend(socket,
                             create_message(MSG_TYPE_AKA,
                                            parsed_message[:src_id],
                                            @parent.mynode.id))) < 0
            error("fail to send AckKeepAlive. errno:#{retval}")
            finish
            return
          end
          # Finish the thread.
          debug("KeppAlive: finish KeepAlive process")
          finish
        end
      end
    end
  end
end
