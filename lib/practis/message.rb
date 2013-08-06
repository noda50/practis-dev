#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'json'

require 'practis'
require 'practis/net'

module Practis
  module Message

    #class << self
    include Practis
    #end

    include Net

    MSG_TYPE_ACK = "ACK"
    MSG_TYPE_JP = "JOIN_PRACTIS"
    MSG_TYPE_ASS = "ACK_SEND_SETTING"
    MSG_TYPE_ARS = "ACK_RECV_SETTING"
    #MSG_TYPE_LP = "LEAVE_PRACTIS"
    #MSG_TYPE_ALP = "ACK_LEAVE_PRACTIS"
    MSG_TYPE_RQE = "REQ_EXECUTABLE"
    MSG_TYPE_ASE = "ACK_SEND_EXECUTABLE"
    #MSG_TYPE_ARCE = "ACK_RECV_EXECUTABLE"
    MSG_TYPE_RP = "REQ_PARAMETERS"
    MSG_TYPE_ASP = "ACK_SEND_PARAMETERS"
    MSG_TYPE_ARP = "ACK_RECV_PARAMETERS"
    #MSG_TYPE_US = "UPDATE_SETTING"
    #MSG_TYPE_AUS = "ACK_UPDATE_SETTING"
    #MSG_TYPE_AE = "ABORT_EXECUTION"
    #MSG_TYPE_AAE = "ACK_ABORT_EXECUTION"
    #MSG_TYPE_RSE = "RESTART_EXECUTION"
    #MSG_TYPE_ARSE = "ACK_RESTART_EXECUTION"
    MSG_TYPE_KA = "KEEP_ALIVE"
    MSG_TYPE_AKA = "ACK_KEEP_ALIVE"
    MSG_TYPE_UPR = "UPLOAD_RESULT"
    MSG_TYPE_STE = "START_EXECUTION"
    # MSG_TYPES = [MSG_TYPE_ACK,
                 # MSG_TYPE_JP, MSG_TYPE_ASS, MSG_TYPE_ARS, MSG_TYPE_LP,
                 # MSG_TYPE_ALP, MSG_TYPE_RQE, MSG_TYPE_ASE, MSG_TYPE_ARCE,
                 # MSG_TYPE_RP, MSG_TYPE_ASP, MSG_TYPE_ARP, MSG_TYPE_US,
                 # MSG_TYPE_AUS, MSG_TYPE_AE, MSG_TYPE_AAE, MSG_TYPE_RSE,
                 # MSG_TYPE_ARSE, MSG_TYPE_KA, MSG_TYPE_AKA]

    MSG_STATUS_OK = "OK"
    MSG_STATUS_FAILED = "FAILED"
    MSG_STATUSES = [MSG_STATUS_OK, MSG_STATUS_FAILED]

    MSG_DEFINITION = [
      {:type => MSG_TYPE_ACK, :attr => [:status]},
      {:type => MSG_TYPE_JP, :attr => [:node_type, :addr, :parallel]},
      {:type => MSG_TYPE_ASS, :attr => [:partial_tree, :keepalive_duration,
                                        :executable_command, :executable_path,
                                        #:result_accessor]},
                                        :result_fields]},
      {:type => MSG_TYPE_ARS, :attr => [:status]},
      {:type => MSG_TYPE_RQE, :attr => []},
      {:type => MSG_TYPE_ASE, :attr => [:executables]},
      {:type => MSG_TYPE_RP, :attr => [:request_number]},
      {:type => MSG_TYPE_ASP, :attr => [:parameters]},
      {:type => MSG_TYPE_ARP, :attr => [:status]},
      {:type => MSG_TYPE_KA, :attr => [:queueing, :executing]},
      {:type => MSG_TYPE_AKA, :attr => []},
      {:type => MSG_TYPE_UPR, :attr => [:result_id, :execution_time, :fields]},
      {:type => MSG_TYPE_STE, :attr => [:result_id]}
    ]
    MSG_COMMON_ATTR = [:type, :src_id, :dst_id]
    #MSG_TYPES = MSG_DEFINITION.collect {|h| h[:type]}
    MSG_TYPES = [MSG_TYPE_ACK, MSG_TYPE_JP, MSG_TYPE_ASS, MSG_TYPE_ARS,
                 MSG_TYPE_RQE, MSG_TYPE_ASE, MSG_TYPE_RP, MSG_TYPE_ASP,
                 MSG_TYPE_ARP, MSG_TYPE_KA, MSG_TYPE_AKA, MSG_TYPE_UPR,
                 MSG_TYPE_STE]

    #=== Parse a JSON message to Hash message.
    #json :: A string json message.
    #returned_value :: On success, a hash object is returned. On error, nil is
    #returned, or an exception is raised.
    def json_to_message(json)
      unless json.kind_of?(String)
        error("invalid type of json. #{json.class.name}")
        return nil
      end
      if json == ""
        error("empty json.")
        return nil
      end
      begin
        hash = JSON.parse(json, :symbolize_names => true)
      rescue Exception => e
        error("JSON.parse failed. #{e.message}")
        error(e.backtrace)
        raise e
      end
      return hash
    end

    #=== check the message attributes depends on type.
    #msg :: checked message.
    #returned_value :: On success, it returns zero. On error, it returns an
    #error code in negative value.
    def check_message_attr(msg)
      return -1 unless msg.kind_of?(Hash)
      MSG_COMMON_ATTR.each { |a|
        return -2 unless msg.has_key?(a) }
      (MSG_DEFINITION.find {|m| m[:type] == msg[:type]})[:attr].each { |a|
        return -3 unless msg.has_key?(a) }
      return 0
    end

    #=== create a message with attributes.
    #type :: message type.
    #src_id :: node id of message sender.
    #dst_id :: destination node id.
    #args :: arguments as a hash.
    #returned_value :: the message in JSON format.
    def create_message(type, src_id, dst_id, *args)
      hash, json = {}, nil
      MSG_COMMON_ATTR.each { |a| hash[a] = eval("#{a}") }
      md = MSG_DEFINITION.select { |d| d[:type] == type }
      md[0][:attr].zip(args).each { |a| hash[a[0]] = a[1] }
      begin
        json = JSON.generate(hash)
      rescue Exception => e
        error("fail to create JSON message. #{e.message}")
        error(e.backtrace)
        raise e
      end
      return json
    end

    #=== parse a JSON message to a hash object.
    #msg :: a JSON message.
    #returned_value :: a message in a hash object.
    def parse_message(msg)
      hash = json_to_message(msg)
      if (retval = check_message_attr(hash)) < 0
        error("attribute error with errno #{retval}")
      end
      return hash
    end

    #=== Wrapper function of Practis::Net::send_message
    #sock :: a socket that send the message.
    #msg :: the sent message.
    #timeout :: a timeout seconds.
    #returned_value :: On success, the sent message length is returned. On
    #error, negative value is returned. -1 means that the method fails with
    #send_message exception. -2 means that the method fails with parse error of
    #JSON. -3 means that the method fails with receiving correct stateus from
    #the receiver.
    def psend(sock, msg, timeout=nil)
      begin
        retval = nil
        if timeout
          timeout = DEFAULT_SEND_TIMEOUT if timeout < 0
          Timeout::timeout(timeout) do
            retval = send_message(sock, msg)
          end
        else
          retval = send_message(sock, msg)
        end
        data = nil
        if timeout
          Timeout::timeout(timeout) do
            data = recv_message(sock)
          end
        else
          data = recv_message(sock)
        end
        if (parsed = parse_message(data)).nil?
          error("fail to parse message.")
          return -2
        end
        if parsed[:status] == MSG_STATUS_OK
          return retval
        else
          return -3    # MSG_STATUS_FAILED
        end
      rescue Timeout::Error
        error("psend failed with timeout.")
        return -4
      rescue Exception => e
        error("fail psend. #{e.message}")
        error(e.backtrace)
        return -1
      end
    end

    #=== Wrapper function of Practis::Net::recv_message
    #sock :: a socket that receive the message.
    #timeout :: a timeout seconds.
    #returned_value :: On success, the received message is returned. On error,
    #negative value is returned. -1 means that the method fails with
    #recv_message exception. -2 means that the method fails with parse error of
    #JSON. -3 means that the method fails with sending the stateus to the
    #sender.
    def precv(sock, timeout=nil)
      begin
        msg = nil
        if timeout
          timeout = DEFAULT_RECV_TIMEOUT if timeout < 0
          Timeout::timeout(timeout) do
            msg = recv_message(sock)
          end
        else
          return -2 if (msg = recv_message(sock)).nil?
        end
        retval = parse_message(msg)
        return -3 if retval.nil?
        msg = create_message(MSG_TYPE_ACK, retval[:dst_id], retval[:src_id],
                             MSG_STATUS_OK)
        data = nil
        if timeout
          Timeout::timeout(timeout) do
            data = send_message(sock, msg)
          end
        else
          data = send_message(sock, msg)
        end
        if data == msg.length
          return retval
        else
          return -4   # fail to send_message
        end
      rescue Exception => e
        error("fail precv. #{e.message}")
        error(e.backtrace)
        return -1
      end
    end

    module_function :parse_message
  end
end
