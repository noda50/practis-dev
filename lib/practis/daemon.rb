#!/usr/bin/ruby
# -*- coding: utf-8 -*-

require 'thread'

require 'practis/configuration_parser'
require 'practis/message_handler'
require 'practis/net'
require 'practis/practis_logger'

module Practis

  #=== Abstract class for Manager, Controller and Executor.
  class Daemon

    include Net
    include Message
    include Practis

    # ClusterNode object of my node.
    attr_reader :mynode
    # To control from outside.
    attr_accessor :running
    # Overall or partial the cluster tree.
    attr_reader :cluster_tree
    # keepalive duration (seconds)
    attr_reader :keepalive_duration
    # PractisLogger
    attr_reader :logger
    # Configuration
    attr_reader :config
    # timeout (seconds)
    attr_reader :loop_sleep_duration
    # Mutex
    attr_accessor :mutex
    # Time.now
    attr_reader :start_time

    #=== Initialize method.
    def initialize(config_file = nil, debug = false)
      @start_time = Time.now
      @running = true
      # Parse and set configurations
      if config_file.nil?
        @config = nil
        @loop_sleep_duration = DEFAULT_LOOP_SLEEP_DURATION
        $logger = (debug ?
                   Practis::PractisLogger.new(Logger::DEBUG, STDERR) :
                   Practis::PractisLogger.new) ;
      else
        case File.extname(config_file)
        when ".xml"
          @config = Practis::Parser::XmlConfigurationParser.new(config_file)
        when ".json"
          @config = Practis::Parser::JsonConfigurationParser.new(config_file)
        end
        if @config.parse < 0
          error("failed to parse configuration file.")
          finalize
        end
        if (@loop_sleep_duration = @config.read("loop_sleep_duration").to_i).nil?
          @loop_sleep_duration = DEFAULT_LOOP_SLEEP_DURATION
        end
        unless $logger
          $logger = Practis::PractisLogger.new(@config.get_debug_level,
                                               @config.get_debug_output,
                                               @config.get_debug_logfile)
        end
        #debug("current configurations: #{@config.configurations}")
      end
      # Mutex
      @mutex = Mutex.new
      # Message queue
      @queue = Queue.new
      trap(:INT) do
        info("SIGINT is received.")
        finalize
        exit(0)
      end
    end

    #=== Main loop.
    #Wait timeout seconds and check running or not.
    def loop
      while true
        break unless running
        mutex.synchronize { update }
        Thread::pass() ### [2013/09/07 I.Noda]
        sleep(@loop_sleep_duration)
      end
    end


    #=== Stop this daemon
    #Stop the message handler and exit.
    def finalize
      @running = false
      info("finish the daemon.")
    end
  end
end
