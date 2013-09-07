#!/usr/bin/ruby
# -*- coding: utf-8 -*-

require 'fileutils'
require 'socket'

require 'practis'
require 'practis/cluster'
require 'practis/daemon'
#require 'practis/database'
require 'practis/executable'
require 'practis/keepalive_thread'
require 'practis/message'
require 'practis/net'
require 'practis/parameter'


module Practis

  #=== Executor daemon.
  #
  #Executor manages a computer cluster that executes allocated parameters from
  #Manager or Controller.
  class Executor < Daemon

    # Parallel number that this Executor can execute.
    attr_accessor :parallel
    # Number of queueing parameters
    attr_accessor :queueing
    # Queueing parameters
    attr_reader :parameter_queue
    # Number of executing parameters
    attr_accessor :executing
    # Executing parameters as thread
    attr_accessor :process
    # IP address of myself
    attr_reader :myaddr
    # Manager IP address
    attr_reader :manager_addr
    # Executable and arguments
    attr_accessor :executable_array
    attr_reader :executable_path

    #=== Initialize method
    #config_file :: a practis configuration file.
    #manager_addr :: specify the IP address of Manager.
    #myaddr :: specify the IP address, if you want to use the interface.
    def initialize(manager_addr = "localhost", myaddr = nil, parallel = 1,
                   debug = false)
      super(nil, debug)
      debug("start to initialize executor, manager address: #{manager_addr}, " +
            "my address: #{myaddr}, parallel: #{parallel}, debug: #{debug}")
      @parallel = chk_arg(Integer, parallel)
      @queueing = chk_arg(Integer, 0)
      @parameter_queue = Queue.new
      @executing = chk_arg(Integer, 0)
      @process = Practis::ExecutableGroup.new
      @myaddr = myaddr.nil? ? chk_arg(String, get_my_address) :
        chk_arg(String, myaddr)
      @manager_addr = chk_arg(String, manager_addr)
      debug("manager: #{@manager_addr}")
      @executable_array = []
      # Join Practis!
      while true
        retval = nil
        @mutex.synchronize { retval = join_practis }
#        break if retval >= 0
        break if retval == true ; ## using new return values
        warn("fail to join practis.")
        warn("retry after few seconds...")
        sleep DEFAULT_KEEPALIVE_DURATION
      end
      # KeepAlive Send Handler
      @keepalive_duration ||= DEFAULT_KEEPALIVE_THREAD_DURATION
      @keepalive_thread = KeepAliveThread.new(
        self,
        @manager_addr,
        @keepalive_duration)
      # Request executables to manager or parent node
      request_executable
      debug("finish to initialize executor.")
    end

    #=== Join Practis process
    #returned_value :: On success, 0 is returned. On error, negative error
    #number is returned.
    def join_practis
      join_practis_itk
    end

    #Okada's original.  This should be obsolute.
    def join_practis_okd
      debug("try to connect #{@manager_addr} to start JoinPractis process.")
      if (sock = get_clnt_sock(
          @manager_addr,
          JOIN_PRACTIS_PORT,
          DEFAULT_SEND_TIMEOUT,
          DEFAULT_RECV_TIMEOUT,
          @myaddr)).nil?
        error("fail to get client socket.")
        return -1
      end
      debug("send JoinPractis message.")
      if (retval = psend(sock, create_message(
          MSG_TYPE_JP, -1, 1, NODE_TYPE_EXECUTOR, @myaddr, @parallel))) < 0
        error("fail to send JoinPractis message. errno: #{retval}")
        close_sock(sock)
        return -2
      end
      debug("send JoinPractis returned value: #{retval}")
      # Receive AckSendSetting
      debug("receive AckSendSetting")
      unless (data = precv(sock)).kind_of?(Hash)
        error("fail to receive AckSendSetting. errno: #{data}.")
        close_sock(sock)
        return -3
      end
      # Create partial tree
      debug("parsed partial_tree: #{data[:partial_tree]}")
      if data[:partial_tree] == "null"  # nil.to_json = "null"
        error("invalid partial tree in received data.")
        close_sock(sock)
        return -4
      end
      @cluster_tree = Practis::PartialTree.json_to_object(data[:partial_tree])
      debug("parsed partial_tree " + cluster_tree.to_json)
      if cluster_tree.nil?
        error("Parsed partial tree is null")
        close_sock(sock)
        return -5
      end
      if data[:dst_id] < MIN_CLUSTER_ID ||
          cluster_tree.mynode[:id] < MIN_CLUSTER_ID ||
          data[:dst_id] != cluster_tree.mynode[:id]
        error("AckSendSetting contains invalid id. #{data[:dst_id]}")
        close_sock(sock)
        return -6
      end
      id = data[:dst_id]
      @keepalive_duration = chk_arg(Integer, data[:keepalive_duration])
      if keepalive_duration < MIN_KEEPALIVE_DURATION ||
          keepalive_duration > MAX_KEEPALIVE_DURATION
        error("Invalid keepalive duration")
        close_sock(sock)
        return -7
      end
      @executable_path = data[:executable_path]
      debug(@executable_path)
      data[:executable_command].split(/\s* \s*/).each do |a|
        @executable_array.push(a)
      end
      debug(@executable_array)
      # Result query
      #@result_accessor = data[:result_accessor]
      @result_fields = data[:result_fields]
      # Send AckRecvSetting
      if (retval = psend(sock, create_message(
          MSG_TYPE_ARS, id, data[:src_id], MSG_STATUS_OK))) < 0
        error("fail to send AckRecvSetting message.")
        close_sock(sock)
        return -8
      end
      close_sock(sock)
      return 0
    end

    #--- join_practis_itk
    #    Noda's version.
    def join_practis_itk
      debug("try to connect #{@manager_addr} to start JoinPractis process.")
      res = get_clnt_sock(@manager_addr,
                          JOIN_PRACTIS_PORT,
                          DEFAULT_SEND_TIMEOUT,
                          DEFAULT_RECV_TIMEOUT,
                          @myaddr){
        |sock|
        #-----
        debug("send JoinPractis message.")
        if (retval = 
            psend(sock, 
                  create_message(MSG_TYPE_JP, -1, 1, 
                                 NODE_TYPE_EXECUTOR, 
                                 @myaddr, @parallel))) < 0
          error("fail to send JoinPractis message. errno: #{retval}")
          return :error_failToSendJointPractis ;
        end
        #-----
        debug("send JoinPractis returned value: #{retval}")
        # Receive AckSendSetting
        debug("receive AckSendSetting")
        unless (data = precv(sock)).kind_of?(Hash)
          error("fail to receive AckSendSetting. errno: #{data}.")
          return :error_failToReceiveAckSendSetting ;
        end
        #-----
        # Create partial tree
        debug("parsed partial_tree: #{data[:partial_tree]}")
        if data[:partial_tree] == "null"  # nil.to_json = "null"
          error("invalid partial tree in received data.")
          return :error_invaridPartialTree ;
        end
        #-----
        @cluster_tree = Practis::PartialTree.json_to_object(data[:partial_tree])
        debug("parsed partial_tree " + cluster_tree.to_json)
        if cluster_tree.nil?
          error("Parsed partial tree is null")
          return :error_nullPartialTree ;
        end
        #-----
        if data[:dst_id] < MIN_CLUSTER_ID ||
            cluster_tree.mynode[:id] < MIN_CLUSTER_ID ||
            data[:dst_id] != cluster_tree.mynode[:id]
          error("AckSendSetting contains invalid id. #{data[:dst_id]}")
          return :error_invalidIdInAckSendSetting ;
        end
        #-----
        id = data[:dst_id]
        @keepalive_duration = chk_arg(Integer, data[:keepalive_duration])
        if keepalive_duration < MIN_KEEPALIVE_DURATION ||
            keepalive_duration > MAX_KEEPALIVE_DURATION
          error("Invalid keepalive duration")
          return :error_invalidKeepaliveDuration;
        end
        #-----
        @executable_path = data[:executable_path]
        debug(@executable_path)
        data[:executable_command].split(/\s* \s*/).each do |a|
          @executable_array.push(a)
        end
        #-----
        debug(@executable_array)
        # Result query
        #@result_accessor = data[:result_accessor]
        @result_fields = data[:result_fields]
        # Send AckRecvSetting
        if (retval = 
            psend(sock, 
                  create_message(MSG_TYPE_ARS, id, data[:src_id], 
                                 MSG_STATUS_OK))) < 0
          error("fail to send AckRecvSetting message.")
          return :error_failToSendAckRecvSetting;
        end
        true ;
      }
      if(res.nil?)
        error("fail to get client socket.")
        return :error_failToGetClientSocket ;
      else
        return res ;
      end
    end


    #=== Request Executable process

    def request_executable
      request_executable_itk
    end

    # Okada's original. This should be obsolute.
    def request_executable_okd
      debug("try to connect #{@manager_addr} to start RequestExecutable " +
            "process.")
      if (sock = get_clnt_sock(
          @cluster_tree.parent[:address],
          REQ_EXECUTABLE_PORT,
          DEFAULT_SEND_TIMEOUT,
          DEFAULT_RECV_TIMEOUT,
          @myaddr)).nil?
        error("fail to get client socket.")
        return -1
      end
      debug("send JoinPractis message")
      if (retval = psend(sock, create_message(MSG_TYPE_RQE,
                                              @cluster_tree.mynode[:id],
                                              @cluster_tree.parent[:id]))) < 0
        error("fail to send JoinPractis message. errno: #{retval}")
        close_sock(sock)
#        -1
        return -1 #### [2013/09/07 I.Noda]
      end
      # Receive AckReqExecutable
      debug("receive AckReqExecutable")
      unless (data = precv(sock)).kind_of?(Hash)
        error("fail to receive AckReqExecutable. errno: #{data}.")
        close_sock(sock)
#        -2
        return -2 #### [2013/09/07 I.Noda]
      end
      data[:executables].each do |executable|
        # write the file into executable path.
        FileUtils.mkdir_p(@executable_path) unless File.exist?(@executable_path)
        filename = [@executable_path, executable[:executable_name]]
            .join(File::SEPARATOR)
        File.delete(filename) if File.exist?(filename)
        debug("create executable file: #{filename}")
        f = File.new(filename, "wb")
        f.write([executable[:executable_binary]].pack(CONVERT_FORMAT))
        f.close
        if File.extname(filename) == ".zip"
          if zip_uncarchive(filename, File::dirname(filename)) < 0
            error("fail to unzip the executable file: #{filename}")
            next
          end
        end
      end
      close_sock(sock)
    end

    #--- request_executable_itk()
    #    new version of request_executable using block of get_clnt_sock.
    def request_executable_itk ## Noda's version
      debug("try to connect #{@manager_addr} to start RequestExecutable " +
            "process.")
      res = get_clnt_sock(@cluster_tree.parent[:address],
                          REQ_EXECUTABLE_PORT,
                          DEFAULT_SEND_TIMEOUT,
                          DEFAULT_RECV_TIMEOUT,
                          @myaddr){ 
        |sock|
        #-----
        debug("send JoinPractis message")
        if (retval = psend(sock, create_message(MSG_TYPE_RQE,
                                                @cluster_tree.mynode[:id],
                                                @cluster_tree.parent[:id]))) < 0
          error("fail to send JoinPractis message. errno: #{retval}")
          return :error_failToSendJoinPractis ;
        end
        #-----
        # Receive AckReqExecutable
        debug("receive AckReqExecutable")
        unless (data = precv(sock)).kind_of?(Hash)
          error("fail to receive AckReqExecutable. errno: #{data}.")
          return :error_failToReceiveAckReqExecutable ;
        end
        #-----
        data[:executables].each do |executable|
          # write the file into executable path.
          FileUtils.mkdir_p(@executable_path) unless File.exist?(@executable_path)
          filename = ([@executable_path, executable[:executable_name]].
                      join(File::SEPARATOR));
          File.delete(filename) if File.exist?(filename)
          debug("create executable file: #{filename}")
          File.open(filename, "wb"){|f|
            f.write([executable[:executable_binary]].pack(CONVERT_FORMAT))
          }
          if File.extname(filename) == ".zip"
            if zip_uncarchive(filename, File::dirname(filename)) < 0
              error("fail to unzip the executable file: #{filename}")
              next ;
            end
          end
        end
        true ;
      }
      if(res.nil?) then
        error("fail to get client socket.")
        return :error_cantGetClientSocket ;
      else
        return res ;
      end
    end

    #=== Request Parameter process
    def request_parameter
      request_parameter_okd
    end

    # Okada's original. This should be obsolute.
    def request_parameter_okd
      debug("Request new proc to parent")
      if (sock = get_clnt_sock(
          cluster_tree.parent[:address],
          REQ_PARAMETERS_PORT,
          DEFAULT_SEND_TIMEOUT,
          DEFAULT_RECV_TIMEOUT,
          @myaddr)).nil?
        error("fail to get client socket.")
        return -1
      end
      debug("send RequestParameter message")
      if (retval = psend(sock, create_message(MSG_TYPE_RP,
          cluster_tree.mynode[:id].to_i, cluster_tree.parent[:id].to_i,
          @parallel - @executing))) < 0
        error("fail to send AckSendParameters. errno:#{retval}")
        close_sock(sock)
        return -2
      end
      debug("receive AckSendParameters")
      unless (data = precv(sock)).kind_of?(Hash)
        error("fail to precv. errno: #{data}")
        close_sock(sock)
        return -3
      end
      debug("receive parameter data: #{data}")
      unless data.kind_of?(Hash)
        error("Invalid AckSendParameters. errno: #{data}")
        close_sock(sock) #### [2013/09/07 I.Noda]
        return -4
      end
      unless (parameters = data[:parameters]).nil?
        if parameters.length > 0
          debug("parameter: #{parameters}")
          begin
            parameters.each do |parameter|
              debug("parameter: #{parameter}")
              @parameter_queue.push(json = JSON.generate(parameter))
              debug("parameter in JSON: #{json}")
            end
          rescue Exception => e
            error("fail to add new parameter. #{e.message}")
            error(e.backtrace)
            close_sock(sock) #### [2013/09/07 I.Noda]
            return -2
          end
        else
          debug("manager reply no available message")
        end
        # Reply Ack
        if (retval = psend(sock, create_message(MSG_TYPE_ARP,
            cluster_tree.parent[:id].to_i, cluster_tree.mynode[:id].to_i,
            MSG_STATUS_OK))) < 0
          error("fail to send AckRequestParaemter with errno #{retval}.")
          close_sock(sock) #### [2013/09/07 I.Noda]
          return -3
        end
      else
        warn("receive invalid AckRequestParaemter message")
        if (retval = psend(sock, create_message(MSG_TYPE_ARP,
            cluster_tree.parent[:id].to_i, cluster_tree.mynode[:id].to_i,
            MSG_STATUS_FAILED))) < 0
          error("fail to send AckRequestParaemter with errno #{retval}.")
          close_sock(sock) #### [2013/09/07 I.Noda]
          return -4
        end
      end
      close_sock(sock) #### [2013/09/07 I.Noda]
      return 0
    end

    #--- request_parameter_itk
    #    Noda's version
    def request_parameter_itk
      debug("Request new proc to parent")
      res = get_clnt_sock(cluster_tree.parent[:address],
                          REQ_PARAMETERS_PORT,
                          DEFAULT_SEND_TIMEOUT,
                          DEFAULT_RECV_TIMEOUT,
                          @myaddr){
        |sock|
        #-----
        debug("send RequestParameter message")
        if (retval = psend(sock, 
                           create_message(MSG_TYPE_RP,
                                          cluster_tree.mynode[:id].to_i, 
                                          cluster_tree.parent[:id].to_i,
                                          @parallel - @executing))) < 0
          error("fail to send AckSendParameters. errno:#{retval}")
          return :error_failToSendAckSendParameters ;
        end
        #-----
        debug("receive AckSendParameters")
        unless (data = precv(sock)).kind_of?(Hash)
          error("fail to precv. errno: #{data}")
          return :error_failToPrecv ;
        end
        #-----
        debug("receive parameter data: #{data}")
        unless data.kind_of?(Hash)
          error("Invalid AckSendParameters. errno: #{data}")
          return :error_invaridAckSendParameters ;
        end
        #-----
        unless (parameters = data[:parameters]).nil?
          if parameters.length > 0
            debug("parameter: #{parameters}")
            begin
              parameters.each do |parameter|
                debug("parameter: #{parameter}")
                @parameter_queue.push(json = JSON.generate(parameter))
                debug("parameter in JSON: #{json}")
              end
            rescue Exception => e
              error("fail to add new parameter. #{e.message}")
              error(e.backtrace)
              return :error_failtToAddNewParameter ;
            end
          else
            debug("manager reply no available message")
          end
          #-----
          # Reply Ack
          if (retval = 
              psend(sock, 
                    create_message(MSG_TYPE_ARP,
                                   cluster_tree.parent[:id].to_i, 
                                   cluster_tree.mynode[:id].to_i,
                                   MSG_STATUS_OK))) < 0
            error("fail to send AckRequestParaemter with errno #{retval}.")
            return :error_failtToSendAckRequestParameter ;
          end
        else
          warn("receive invalid AckRequestParaemter message")
          if (retval = 
              psend(sock, 
                    create_message(MSG_TYPE_ARP,
                                   cluster_tree.parent[:id].to_i, 
                                   cluster_tree.mynode[:id].to_i,
                                   MSG_STATUS_FAILED))) < 0
            error("fail to send AckRequestParameter with errno #{retval}.")
            return :error_failToSendAckRequestParameter ;
          end
        end
        true ;
      }
      if(res.nil?)
        error("fail to get client socket.")
        return :error_cantGetClientSocket ;
      else
        return res ;
      end
    end

    #--- update
    #    main routine executed every cycle.
    def update
      update_itk
    end

    # Okada's original
    def update_okd
      # Check keep alive thread
      unless @keepalive_thread.alive?
        warn("keepalive thread not alive")
        @keepalive_thread.join
      end
      # Check executing proc
      info("current running proccess: #{@process.length}")
      @process.update
      if (@executing = @process.length) < @parallel  # Can execute next proc
        if (@queueing = @parameter_queue.size) > 0   # Execute queueing proc
          debug("Execute queueing proc")
          deq_parameter = @parameter_queue.shift()
          debug(@executable_array)
          @process.exec(*@executable_array, deq_parameter.to_s,
                        cluster_tree.mynode[:address],
                        JSON.generate(@result_fields),
                        cluster_tree.mynode[:id].to_s,
                        cluster_tree.parent[:id].to_s,
                        cluster_tree.parent[:address].to_s)
          @executing = @process.length
          parameter = JSON.parse(deq_parameter, :symbolize_names => true)
          if (sock = get_clnt_sock(
              cluster_tree.parent[:address],
              START_EXECUTION_PORT,
              DEFAULT_SEND_TIMEOUT,
              DEFAULT_RECV_TIMEOUT,
              @myaddr)).nil?
            error("fail to get client socket.")
            return -1
          end
          msg = create_message(MSG_TYPE_STE, cluster_tree.mynode[:id].to_i,
                               cluster_tree.parent[:id].to_i,
                               parameter[:uid].to_i,
                               cluster_tree.mynode[:id].to_i)
          debug("send " + msg)
          if (retval = psend(sock, msg)) < 0
            error("fail to send AckSendParameters. errno:#{retval}")
            close_sock(sock)
            return -1
          end
          close_sock(sock) ; #### [2013/09/07 I.Noda]
        else              # Request new proc
          debug("exec: #{@executing}, queue: #{@queueing}, parallel: #{@parallel}")
          if (retval = request_parameter).nil?
            warn("request parameter failed.")
          elsif retval < 0
            warn("request parameter failed with errno #{retval}")
          end
        end
      end
      debug("current cluster tree: #{cluster_tree.to_s}")
    end

    #--- update_itk
    #    Noda's version
    def update_itk
      # Check keep alive thread
      unless @keepalive_thread.alive?
        warn("keepalive thread not alive")
        @keepalive_thread.join
      end
      # Check executing proc
      info("current running proccess: #{@process.length}")
      @process.update
      if (@executing = @process.length) < @parallel  # Can execute next proc
        if (@queueing = @parameter_queue.size) > 0   # Execute queueing proc
          debug("Execute queueing proc")
          deq_parameter = @parameter_queue.shift()
          debug(@executable_array)
          @process.exec(*@executable_array, deq_parameter.to_s,
                        cluster_tree.mynode[:address],
                        JSON.generate(@result_fields),
                        cluster_tree.mynode[:id].to_s,
                        cluster_tree.parent[:id].to_s,
                        cluster_tree.parent[:address].to_s)
          @executing = @process.length
          parameter = JSON.parse(deq_parameter, :symbolize_names => true)
          #-----
          res = get_clnt_sock(cluster_tree.parent[:address],
                              START_EXECUTION_PORT,
                              DEFAULT_SEND_TIMEOUT,
                              DEFAULT_RECV_TIMEOUT,
                              @myaddr){
            |sock|
            msg = create_message(MSG_TYPE_STE, cluster_tree.mynode[:id].to_i,
                                 cluster_tree.parent[:id].to_i,
                                 parameter[:uid].to_i,
                                 cluster_tree.mynode[:id].to_i)
            debug("send " + msg)
            if (retval = psend(sock, msg)) < 0
              error("fail to send AckSendParameters. errno:#{retval}")
              return :error_failToSendAckSendPamareters ;
            end
            true ;
          }
          if(res.nil?) then
            error("fail to get client socket.")
            return :error_failToGetClientSocket
          end
        else              # Request new proc
          debug("exec: #{@executing}, queue: #{@queueing}, parallel: #{@parallel}")
          if (retval = request_parameter).nil?
            warn("request parameter failed.")
          elsif retval < 0
            warn("request parameter failed with errno #{retval}")
          end
        end
      end
      debug("current cluster tree: #{cluster_tree.to_s}")
    end

    def finalize
      info("Executor finalizing process")
      unless @keepalive_thread.nil?
        @keepalive_thread.running = false
        @keepalive_thread.join
      end
      super
    end
  end
end
