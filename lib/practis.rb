#!/usr/bin/ruby
# -*- coding: utf-8 -*-

require 'rubygems'
require 'fileutils'
require 'json'
require 'zipruby'

require 'practis/version'


module Practis

  # Constants

  # The names of node
  NODE_TYPE_MANAGER = "manager"         # Manager node
  NODE_TYPE_CONTROLLER = "controller"   # Controller node
  NODE_TYPE_EXECUTOR = "executor"       # Executor node
  # All node type list.
  NODE_TYPES = [NODE_TYPE_MANAGER, NODE_TYPE_CONTROLLER, NODE_TYPE_EXECUTOR]

  # State of node
  NODE_STATE_READY = "ready"
  NODE_STATE_WAITING = "waiting"
  NODE_STATE_RUNNING = "running"
  NODE_STATE_TIMEOUT = "timeout"
  NODE_STATE_FINISH = "finish"

  # Max number of cluster node.
  MAX_NODES = 1024
  # Max number of project.
  MAX_PROJECT = 128
  # Max number of execution.
  MAX_EXECUTION = 1024

  # Limit of ID
  MIN_CLUSTER_ID = 1
  MAX_CLUSTER_ID = MIN_CLUSTER_ID + MAX_NODES

  # Used for parameter set ID generation
  PARAMETER_ID_DURATION = 65535

  # Handler timeout
  DEFAULT_MESSAGE_HANDLER_DURATION = 1

  # Sleep time (seconds) of Daemon object in loop method
  DEFAULT_LOOP_SLEEP_DURATION = 1

  # Duration (seconds) of keep alive
  DEFAULT_KEEPALIVE_DURATION = 3
  # Duration (seconds) to determine that a node is down
  DEFAULT_KEEPALIVE_EXPIRED_DURATION = DEFAULT_KEEPALIVE_DURATION * 3
  # Duration (seconds) of KeepAliveThread sends the message.
  DEFAULT_KEEPALIVE_THREAD_DURATION = 3

  # Parameters of keepalive
  DEFAULT_PARAMETER_EXPIRED_TIMEOUT = 30
  DEFAULT_KEEPALIVE = 15
  MIN_KEEPALIVE_DURATION = 1
  MAX_KEEPALIVE_DURATION = 600

  # Waiting time of join for a finalizing thread.
  THREAD_FINIALIZE_TIMEOUT = 1

  # Tags or attributes used in XML files.
  NAME_ATTR = "name"
  DATA_TYPE_ATTR = "data_type"

  # Data type
  DATA_TYPE_INTEGER = "Integer"
  DATA_TYPE_FLOAT = "Float"
  DATA_TYPE_STRING = "String"
  DATA_TYPES = [DATA_TYPE_INTEGER, DATA_TYPE_FLOAT, DATA_TYPE_STRING]

  # Parameter state (used by Practis::Parameter)
  PARAMETER_STATE_READY = "ready"
  PARAMETER_STATE_ALLOCATING = "allocating"
  PARAMETER_STATE_EXECUTING = "executing"
  PARAMETER_STATE_FINISH = "finish"
  PARAMETER_STATES = [PARAMETER_STATE_READY, PARAMETER_STATE_EXECUTING,
    PARAMETER_STATE_FINISH]

  RANGE_START = "start"
  RANGE_END = "end"
  RANGE_STEP = "step"
  INCLUDE_RANGE = "include_range"
  EXCLUDE_RANGE = "exclude_range"
  INCLUDE_LIST = "include_list"
  EXCLUDE_LIST = "exclude_list"

  # Databases
  DB_PROJECT = "project"
  DB_EXECUTION = "execution"
  DB_EXECUTABLE = "executable"
  DB_NODE = "node"
  DB_PARAMETER = "parameter"
  DB_RESULT = "result"
  DATABASE_LIST = [DB_PROJECT, DB_EXECUTION, DB_EXECUTABLE, DB_NODE,
      DB_PARAMETER, DB_RESULT]
  QUERY_RETRY_TIMES = 5           # times to retry
  QUERY_RETRY_DURATION = 1        # duration till retry

  #== Web Interfaces
  # parameter progress overview report max step
  DEFAULT_PROGRESS_OVERVIEW_MAXSTEP = 10 ;


  # Convert a binary to a string.
  CONVERT_FORMAT = "H*"

  def string_to_type(str)
    Module.const_get(str)
  end

  def type_to_string(type)
    type.to_s
  end

  def type_to_format(type)
    case type
    when "Integer" then "%d"
    when "String" then "%s"
    when "LongString" then "%s"
    when "Float" then "%f"
    when "Double" then "%f"
    else nil
    end
  end

  def type_to_sqltype(type)
    case type
    #when "Integer" then "int(11)"
    when "Integer" then "int"
    when "String" then "text"
    when "LongString" then "longtext"
    when "Float" then "float"
    when "Double" then "double"
    else nil
    end
  end

  #=== Argument type check.
  #type :: class such as Integer, String...
  #argument :: checked argument.class
  #allow_nil :: the argument allow nil object or not.
  #returned_value :: argument
  def chk_arg(type, argument, allow_nil = false)
    raise ArgumentError.new("Argument is nil, but nil is not permitted.") \
      if argument.nil? && !allow_nil
    raise ArgumentError.new("#{type} is expected. But was #{argument.class}") \
      if !argument.nil? && !argument.kind_of?(type)
    argument
  end

  #=== Convert an unix time to ISO time format string.
  #time :: unix time
  #returned_value :: ISO time format string.
  def iso_time_format(time)
    Time.at(time).strftime("%Y-%m-%d %H:%M:%S")
  end

  #=== Wrapper function of Practis::Net::send_message
  #sock :: connected socket
  #msg :: sent message
  #returned_value :: On success, it returns sent data size. On error, a negative
  #error code is returned.
  def send_practis(sock, msg)
    if (retval = send_message(sock, msg)) == msg.length
      (data = recv_message(sock)).kind_of?(String) ? retval : data
    else
      retval
    end
  end

  #=== Wrapper function of Practis::Net::recv_message
  #sock :: connected socket
  #returned_value :: On success, it returns received data. On error, it returns
  #an error.
  def recv_practis(sock)
    if (retval = recv_message(sock)).kind_of?(String)
      msg = create_ack_message
      (data = send_message(sock, msg)) == msg.length ?  retval : data
    else
      retval
    end
  end

  #=== Archive a file or a directory to a zip file.
  #input :: input file or directory
  #output :: output zip file
  #overwrite :: overwrite if output exists.
  #returned_value :: On success, it returns zero. On error, it returns negative
  #value.
  def zip_archive(input, output, overwrite = false)
    return -1 unless File.exist?(input)
    if File.exist?(output_file = File.join(File::dirname(input), output)) &&
        !overwrite
      return -2
    end
    File.delete(output_file) if File.exist?(output_file) && overwrite
    Dir.chdir(File::dirname(input)) do
      Zip::Archive.open(output, Zip::CREATE) do |ar|
        ar.add_dir(basename = File::basename(input))
        Dir.glob(File.join(basename, "/**/*")).each do |path|
          File.directory?(path) ?  ar.add_dir(path) : ar.add_file(path, path)
        end
      end
    end
    return 0
  end

  #=== Unarchive a zip file.
  #input :: input zip file.
  #output :: output directory.
  #returned_value :: On success, it returns zero. On error, it returns negative
  #value.
  def zip_uncarchive(input, output)
    return -1 unless File.exist?(input)
    return -2 unless File.directory?(output)
    Zip::Archive.open(input) do |ar|
      ar.each do |zf|
        if zf.directory?
          FileUtils.mkdir_p(File.join(output, zf.name))
        else
          dirname = File.dirname(File.join(output, zf.name))
          FileUtils.mkdir_p(dirname) unless File.exist?(dirname)
          open(File.join(output, zf.name), "wb") { |f| f << zf.read }
        end
      end
    end
    return 0
  end

  #=== Wrapper of fatal method in PractisLogger.
  def fatal(str, *args)
    if $logger
      !str.kind_of?(String) ? $logger.fatal("#{str}") :
        $logger.fatal(str, *args)
    else
      STDERR.printf("#{str}\n", *args)
    end
  end

  #=== Wrapper of error method in PractisLogger.
  def error(str, *args)
    if $logger
      !str.kind_of?(String) ? $logger.error("#{str}") :
        $logger.error(str, *args)
    else
      STDERR.printf("#{str}\n", *args)
    end
  end

  #=== Wrapper of warn method in PractisLogger.
  def warn(str, *args)
    if $logger
      !str.kind_of?(String) ? $logger.warn("#{str}") : $logger.warn(str, *args)
    else
      STDERR.printf("#{str}\n", *args)
    end
  end

  #=== Wrapper of info method in PractisLogger.
  def info(str, *args)
    if $logger
      !str.kind_of?(String) ? $logger.info("#{str}") : $logger.info(str, *args)
    else
      STDERR.printf("#{str}\n", *args)
    end
  end

  #=== Wrapper of debug method in PractisLogger.
  def debug(str, *args)
    if $logger
      !str.kind_of?(String) ? $logger.debug("#{str}") :
        $logger.debug(str, *args)
    else
      STDERR.printf("#{str}\n", *args)
    end
  end

  #=== Common to_s method.
  #Generate a string including class variables.
  def to_s
    str = ""
    self.instance_variables.each do |v|
      case self.instance_variable_get(v).class.to_s
      when "Array"
        str << "#{v.slice(1, v.length)}: ["
        self.instance_variable_get(v).each {|a| str << a.to_s + ", " }
        str = str.slice(0, str.length - 2)
        str << "], "
      else
        str << "#{v.slice(1, v.length)}: #{self.instance_variable_get(v).to_s}, "
      end
    end
    str.slice(0, str.length - 2)
  end

  #=== Common to_json method.
  def to_json(obj=nil)
    hash = {}
    self.instance_variables.each do |v|
      v_name = v.to_s.delete("@")
      hash[v_name.to_sym] = self.instance_variable_get(v)
    end
    JSON.generate(hash)
  end

  #=== Parse the arguments called from an executor.
  #args :: ARGV called from an executor.
  #returned_value :: a hash including 
  def parse_executor_arguments(args)
    if !args.instance_of?(Array) || args.length != 6
      error("invalid args")
      return nil
    end
    hash = {}
    hash[:start_time] = Time.now
    json = JSON.parse(args[0], :symbolize_names => true)
    hash[:uid] = json[:uid]
    hash[:parameter_set] = json[:parameter_set]
    hash[:addr] = args[1]
    debug(args[2])
    hash[:result_fields] = JSON.parse(args[2], :symbolize_names => true)
    hash[:executor_id] = args[3].to_i
    hash[:parent_id] = args[4].to_i
    hash[:parent_addr] = args[5]
    hash
  end

  #=== Upload the result to a parent node.
  #args :: argument_hash created by parse_executor_arguments method.
  #returned_value :: On success, it returns zero. On error, it returns -1.
  def upload_result(args)
    execution_time = Time.now - args[:start_time]
    include Message, Net
    msg = create_message(MSG_TYPE_UPR, args[:executor_id], args[:parent_id],
                         args[:uid], execution_time, args[:results])
    if (sock = get_clnt_sock(args[:parent_addr], UPLOAD_RESULT_PORT)).nil?
      error("fail to get client socket.")
      return -1
    end
    if (retval = psend(sock, msg)) < 0
      error("fail to send UploadResult message. errno: #{retval}")
      close_sock(sock)
      return -2
    else
      close_sock(sock)
      return 0
    end
  end

  module ClassMethods

    #=== Common to_json_to_object method.
    #
    #This class method is available for all of the class that includes Practis
    #module except for overrided class. The method calls new method, but does
    #not set any arguments. When you want to use this method for a class that 
    #require arguments for new method, you should override.
    #
    #json :: Json object that create a new object.
    #returned_value :: A new object
    def json_to_object(json)
      hash = JSON.parse(json, :symbolize_names => true)
      obj = self.new
      obj.instance_variables.each do |v|
        obj.instance_variable_set(v, hash[v.to_sym])
      end
      obj
    end
  end

  def self.included(cls)
    cls.extend ClassMethods
  end

  module_function :fatal, :error, :info, :warn, :debug
end
