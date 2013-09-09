#!/usr/bin/env ruby
# -*- conding: utf-8 -*-

require 'socket'

require 'practis'
require 'practis/handler'
require 'practis/message'
require 'practis/net'


module Practis
  module Net

    #=== Notify alive to practis.
    class KeepAliveThread < Thread

      include Net
      include Handler
      include Message
      include Practis

      # To control from outside.
      attr_accessor :running
      attr_accessor :parent
      attr_accessor :timeout

      def initialize(parent, manager_addr, timeout=1)
        @parent = parent
        @timeout = timeout
        @socket = nil
        @running = true
        super(&method(:thread))
      end

      private
      def thread
        debug("start keepalive thread")
        src_id, dst_id = -1, -1
        @parent.mutex.synchronize {
          while @parent.cluster_tree.parent.nil?
            debug("wait until partial tree is initialized...")
            sleep @timeout
          end
          src_id = @parent.cluster_tree.mynode[:id]
          dst_id = @parent.cluster_tree.parent[:id] \
            unless @parent.cluster_tree.parent.nil?
          debug("dst_id: #{dst_id}, src_id: #{src_id}")
        }
        while true
          debug("keppalive send process")
          (info("#{self.class.name} is not running."); break) unless @running
          msg = nil
          (warn("parent is null"); break) if @parent.nil?
          @parent.mutex.synchronize {
            if @parent.cluster_tree.nil?
              warn("partial tree is null")
            elsif @parent.cluster_tree.mynode.nil?
              warn("my node info in partial tree is null")
            else
              msg = create_message(MSG_TYPE_KA, src_id, dst_id,
                                   @parent.queueing, @parent.executing)
            end
          }
          debug("send keepalive message: #{msg}")
          unless msg.nil?
            if (@socket = get_clnt_sock(@parent.manager_addr, KEEP_ALIVE_PORT,
                                        DEFAULT_SEND_TIMEOUT,
                                        DEFAULT_RECV_TIMEOUT,
                                        @parent.myaddr)).nil?
              error("fail to get client socket.")
            else
              if (retval = psend(@socket, msg)) < 0
                error("fail to send KeepAlive message. errno: #{retval}")
              else
                debug("wait ack...")
                error("fail to receive KeepAliveAck message.") \
                  unless (data = precv(@socket)).kind_of?(Hash)
                debug("recv: #{data}")
              end
            end
            close_sock(@socket)
          end
          Thread::pass() ;
          sleep @timeout
        end
      end
    end
  end
end
