#!/usr/bin/env ruby
# -*- conding: utf-8 -*-

require 'socket'
require 'timeout'

require 'practis'
require 'practis/handler'
require 'practis/message'
require 'practis/net'

module Practis
  module Net

    #=== Common message handler for Manager, Controller and Executor.
    # work with rsh|ssh or not.
    class MessageHandler < Thread

      include Handler
      include Message
      include Net
      include Practis

      # To control from outside.
      attr_accessor :running
      attr_accessor :parent
      attr_accessor :select_duration
      attr_reader :handlers

      #=== initialize method.
      #parent :: caller object of this thread.
      #select_duration :: duration seconds every select call.
      def initialize(parent, select_duration=1)
        @parent = parent
        @select_duration = select_duration
        @handlers = []
        @running = true
        info("handler initialized.")
        super(&method(:thread))
      end

      #=== create a new handler.
      #name :: a name of the created handler
      #sock :: a connected socket.
      #returned_value :: On success, it returns zero. On error, it returns -1.
      def createHandler(name, sock)
        @handlers.each { |handler|
          (warn("Same handler already exist: #{name}"); return -1) \
            if handler[:name] == name }
        @handlers << {:name => name, :socket => sock, :thread => nil}
        return 0
      end

      #=== search a handler with a key value pair.
      #key :: a key to search a handler.
      #value :: a value for the key.
      #returned_value :: On success, it returns a searched handler. On error,
      #it returns nil.
      def readHandler(key, value)
        (warn("invalid key: #{key}"); return nil) \
          unless [:name, :socket, :thread].contains?(keytpe)
        @handlers.each { |handler| return handler if handler[key] == value }
        warn("no handler matching key: #{key}, value: #{value}")
        return nil
      end

      #=== update a searched handler with a key value pair.
      #key :: a key to search a handler.
      #value :: a value for the key.
      #update_key :: a key to search a updated value.
      #update_value :: a value for the update_key.
      #returned_value :: On success, it returns zero. On error, it returns a
      #negative value.
      def updateHandler(key, value, update_key, update_value)
        (warn("invalid key: #{key}"); return -1) \
          unless [:name, :socket, :thread].contains?(key)
        (warn("invalid update key: #{update_key}"); return -2) \
          unless [:name, :socket, :thread].contains?(update_key)
        @handlers.each { |handler|
          (handler[update_keytpe] = updated_value; return 0) \
            if handler[key] == value }
        return -3
      end

      #=== delete a handler with a name.
      #name :: a name to search a handler
      #returned_value :: On success, it returns zero. On error, it returns -1.
      def deleteHandler(name)
        @handlers.each do |handler|
          if handler[:name] == name
            handler[:socket].close
            if !handler[:thread].nil? && handler[:thread].alive?
              handler[:thread].running = false
              handler[:thread].join
            end
            @handler.delete(handler)
            return 0
          end
        end
        return -1
      end

      private
      #=== main thread loop process.
      #A message handler call a specified thread when it receives a message. The
      #thread is determined with the type in the message.
      def thread
        debug("start message handler #{@running}")
        sockets = []
        while true
          Thread::pass ## [2013/09/07 I.Noda] 
          unless @running
            info("stop handler with running false")
            break
          end
          @handlers.each do |handler|
            next if handler[:thread].nil?
            unless handler[:thread].alive?
              info("kill handler thread #{handler[:name]}")
              handler[:thread].join
              handler[:thread] = nil;
            end
          end
          sockets.clear
          @handlers.each { |handler|
            handler[:socket].each { |s| sockets.push(s) } }
          debug(" select connections...")
          fds, _, _ = IO::select(sockets, _, _, @select_duration)
          debug(" done: select connections...")
          next if fds == nil
          #debug("select fds: #{fds}")
          fds.each do |socket|
            debug("new connection for #{Socket.unpack_sockaddr_in(socket.getsockname)}")
            next if (sock = accept_sock(socket)).nil?
            debug("new connection accept #{Socket.unpack_sockaddr_in(sock.getpeername)}")
            handler_name = nil
            @handlers.each { |handler|
              (handler_name = handler[:name]; break) \
                if handler[:socket].include?(socket) }
            (debug("null handler"); sock.close; next) if handler_name == nil
            debug("call handler " + handler_name)
            error("handler #{hander_name} cannot find in globals") \
              if (klass = Practis::Net::Handler.const_get(handler_name)).nil?
            th = klass.new(@parent, sock)
            @handlers.each { |handler|
              (handler[:thread] = th; break) if handler[:name] == handler_name }
          end
        end
        # finalize the thread
        info("finalize #{self.class.name}")
        @handlers.each do |handler|
          close_sock(handler[:socket])
          next if handler[:thread].nil?
          if handler[:thread].alive?
            begin
              Timeout::timeout(THREAD_FINIALIZE_TIMEOUT) do
                handler[:thread].running = false
                debug("wait join #{handler[:name]}")
                handler[:thread].join
              end
            rescue Timeout::Error
              debug("thread #{handler[:name]} is killed with timeout.")
              Thread.kill(handler[:thread])
            end
          end
        end
      end
    end
  end
end
