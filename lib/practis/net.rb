#!/usr/bin/ruby
# -*- coding: utf-8 -*-

require 'socket'
require 'timeout'

require 'practis'

module Practis
  module Net

    include Practis

    # Default buffer size (bytes)
    BUF_SIZE = 1024

    # Default timeout seconds of socket option
    DEFAULT_SEND_TIMEOUT = 3
    DEFAULT_RECV_TIMEOUT = 3
    DEFAULT_ACCEPT_TIMEOUT = 3
    DEFAULT_STEP_TIMEOUT = 0.1

    # Port number
    # MessageHandler
    MESSAGE_PORT = 12345
    # JoinPractis process handler
    JOIN_PRACTIS_PORT = 12346
    # LeavePractis process handler
    LEAVE_PRACTIS_PORT = 12347
    # ReqExecutable process handler
    REQ_EXECUTABLE_PORT = 12348
    # ReqParameters process handler
    REQ_PARAMETERS_PORT = 12349
    # UpdateSetting process handler
    UPDATE_SETTING_PORT = 12350
    # AbortExecution process handler
    ABORT_EXECUTION_PORT = 12351
    # RestartExecution process handler
    RESTART_EXECUTION_PORT = 12352
    # KeepAlive process
    KEEP_ALIVE_PORT = 12353
    # UploadResult handler
    UPLOAD_RESULT_PORT = 12354
    # StartExecution handler
    START_EXECUTION_PORT = 12355

    #=== Check rsh is available or not
    #The functionality simply sends rsh command to the specified host using rsh.
    #hostname :: a host name to send a simple echo command through rsh.
    #timeout :: a timeout seconds of sending rsh.
    #returned_value :: 
    def check_rsh(hostname, timeout=1)
      return system(
        %(rsh #{hostname} -t #{timeout} "echo test &> /dev/null" &> /dev/null))
    end

    #=== Check ssh is available or not
    #The functionality simply sends rsh command to the specified host using ssh.
    def check_ssh(hostname)
      return system(
        %(ssh #{hostname} "echo test &> /dev/null" &> /dev/null))
    end

    #=== Get an available my IP address
    #Caution! This method gets just one available IP address. If you will use a
    #computer that has multiple network interfaces, you should specify the
    #interface or address by yourself.
    def get_my_address
      return IPSocket::getaddress(Socket::gethostname)
    end

    #=== Get a connected TCP client socket.
    #hostname :: destination host name.
    #port :: port number
    #send_timeout :: send timeout
    #recv_timeout :: recv timeout
    #local_host :: bind a local host name.
    #local_port :: bind a local port number.
    #returned_value :: client socket
    #&block :: if given, the block is called with a socket, and close. 
    def get_clnt_sock(hostname, port, send_timeout=nil, recv_timeout=nil,
                     local_host=nil, local_port=nil,&block)
      sock = nil
      if local_host || local_port
        begin
          sock = Socket.tcp(hostname, port, local_host, local_port)
        rescue Exception => e
          sock = nil
          warn("fail to connect socket to #{hostname}:#{port} " +
               "with #{local_host}:#{local_port}. #{e.message}")
          warn("try to connect without binding #{local_host}:#{local_port}.")
        end
      end
      if sock.nil?
        begin
          sock = Socket.tcp(hostname, port)
        rescue Exception => e
          error("fail to connect socket #{e.message}")
          error(e.backtrace)
          sock = nil
          return nil
        end
      end
      begin
        psetsockopt(sock, send_timeout, recv_timeout)
      rescue Exception => e
        error("fail to connect socket #{e.message}")
        error(e.backtrace)
        sock.close
        sock = nil
        return nil
      end
      ## If block is given, call it.  Otherwise, return socket.
      if(block)
        # if block is given, call it and close the socket.
        begin
          return block.call(sock) ;
        ensure
          close_sock(sock) ;
        end
      else
        # otherwise, it return the socket. (original version)
        return sock
      end
    end

    #=== Get a TCP server socket.
    #port :: port number
    #send_timeout :: send timeout
    #recv_timeout :: recv timeout
    #local_host :: local host name
    #returned_value :: an array of server sockets IPv4 and IPv6
    #&block :: if given, the block is called with a socket, and close. 
    def get_srv_sock(port, send_timeout=nil, recv_timeout=nil, local_host=nil,
                     &block)
      sock = nil
      if local_host
        begin
          sock = Socket.tcp_server_sockets(local_host, port)
        rescue Exception => e
          sock = nil
          warn("fail to create a server socket with #{local_host}:#{port}. " +
                "#{e.message}")
          #warn(e.backtrace)
          warn("try to create a server socket without local binding.")
        end
      end
      if sock.nil?
        begin
          sock = Socket.tcp_server_sockets(port)
        rescue Exception => e
          error("fail to create server socket #{e.message}")
          error(e.backtrace)
          sock = nil
          raise e
        end
      end
      sock.each do |s|
        begin
          psetsockopt(s, send_timeout, recv_timeout)
        rescue Exception => e
          error("fail to set socket options to a server socket. #{e.message}")
          error(e.backtrace)
          s.close
          s = nil
          raise e
        end
      end
      if sock.nil?
        error("could not create server socket")
        return nil
      end
      ## If block is given, call it.  Otherwise, return socket.
      if(block)
        # if block is given, call it and close the socket.
        begin
          return block.call(sock) ;
        ensure
          close_sock(sock) ;
        end
      else
        # otherwise, it return the socket. (original version)
        return sock
      end
    end

    #=== Set socket options.
    #The practis socket is set socket options such as SO_REUSEADDR, SO_SNDTIMEO,
    #SO_RECVTIMEO.
    #sock :: a socket that is set options.
    #send_timeout :: send timeout (seconds)
    #recv_timeout :: recv timeout (seconds)
    #returned_value :: if succeed, returns 0. Otherwise, an exception is raised.
    def psetsockopt(sock, send_timeout=nil, recv_timeout=nil)
      return -1 if sock.nil?
      begin
        sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
        timeval = nil;
        if send_timeout
          timeval = get_socket_timeout(send_timeout.to_f)
        # else
          # timeval = get_socket_timeout(DEFAULT_SEND_TIMEOUT.to_f)
          sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDTIMEO, timeval)
        end
        if recv_timeout
          timeval = get_socket_timeout(recv_timeout)
        # else
          # timeval = get_socket_timeout(DEFAULT_RECV_TIMEOUT.to_f)
          sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, timeval)
        end
      rescue Exception => e
        error("fail to set socket option. #{e.message}")
        raise e
      end
      return 0
    end

    #=== Wrapper of accept
    #Provide the accept() wrapper method for a socket or an array of a socket. 
    #Usually, timeout should be implemented with select. Please don't use the
    #timeout option, if you don't understand what it does in the code.
    #sock :: Socket or Array of Socket object
    #accept_timeout :: Timeout seconds, if nil, wait till connected.
    #returned_value :: Upon successful completion, accept_sock shall return the
    #connected socket. Otherwise, nil shall be returned or the exception is
    #raised.
    def accept_sock(sock, accept_timeout=nil, send_timeout=nil,
                    recv_timeout=nil)
      if sock.nil?
        error("socket is null")
        return nil
      end
      if sock.kind_of?(Socket)
        s, addr = nil, nil
        if accept_timeout
          begin
            if accept_timeout < 0
              accept_timeout = DEFAULT_ACCEPT_TIMEOUT
            end
            Timeout::timeout(accept_timeout) do
              s, addr = sock.accept
            end
            psetsockopt(sock, send_timeout, recv_timeout)
          rescue Timeout::Error
            error("fail to accept. Timeout.")
            s = nil
          rescue Exception => e
            warn("accept failed. #{e.message}\n")
            error(e.backtrace)
            s = nil
            raise e
          end
        else
          begin
            s, addr = sock.accept
            psetsockopt(s, send_timeout, recv_timeout)
          rescue Exception => e
            error("accept failed. #{e.message}")
            error(e.backtrace)
            s = nil
            raise e
          end
        end
        debug("accept from addr: #{addr.getnameinfo}")
        return s
      elsif sock.kind_of?(Array)
        return accept_srv_sock(sock, accept_timeout)
      else
        error("invalid type of socket. #{sock.class.name}")
        return nil
      end
    end

    #=== Send a string message through a tcp socket.
    #sock :: a connected tcp socket
    #msg :: sent message
    #returned_value :: On success, the message length is returned. On error, -1
    #is returned, or an exception is raised.
    def send_message(sock, msg)
      retval = nil
      begin
        retval = msg.length
        sock.puts(msg)
      rescue Exception => e
        error("fail to send a message. #{e.message}")
        error(e.backtrace)
        raise e
      end
      return retval
    end

    #=== Receive a string message through a tcp socket.
    #sock :: a connected tcp socket
    #returned_value :: On succeess, the recieved message is returned. On error,
    #an exception is raised.
    def recv_message(sock)
      retval = String.new
      # gets till the connection is reset or receiving any data
      begin
        retval = sock.gets
      rescue Exception => e
        error("fail to receive message. #{e.message}")
        error(e.backtrace)
        raise e
      end
      if retval.kind_of?(String)
        return retval.chop
      else
        error("received message is nil")
        caller().each{|c| error("... called from:" + c.to_s)}
        return nil
      end
    end

    #=== Wrapper of IO#close
    #Close a Socket or an Array of Socket object.
    def close_sock(sock)
      return nil if sock.nil?
      case sock.class.name
      when "Socket"
        begin
          sock.shutdown unless sock.closed?
        rescue Exception => e
          if e.class.name != "Errno::ENOTCONN"
            error("fail to shutdown socket. #{e.message}")
            error(e.backtrace)
            raise e
          end
        end
        begin
          sock.close unless sock.closed?
        rescue Exception => e
          error("fail to close socket. #{e.message}")
          error(e.backtrace)
          raise e
        end
      when "Array"    # an array of sockets to handle multiple network interfaces.
        retval = true
        sock.each { |s| retval &= close_sock(s) }
        return retval
      end
      return nil
    end

    #=== Send a file.
    #hostname :: host name
    #port :: port number
    #filename :: sent file name
    #send_timeout :: timeout seconds of the socket.
    #returned_value :: On success, it returns zero. On error, it returns -1.
    def send_file(hostname, port, filename, send_timeout=nil)
      open(filename, "rb") do |file|
        size = File.size(filename)
        return -1 if (sock = get_clnt_sock(hostname, port, send_timeout)).nil?
        sock.puts "PUT_FILE #{filename} #{size}"
        send_sock(sock, file.read)
        sock.close
      end
      return 0
    end

    #=== Receive a file.
    #port :: port number
    #dict :: a directory to save the received file.
    #recv_timeout :: timeout seconds to receive.
    #returned_value :: On success, it returns a received file. On error, it
    #returns nil.
    def recv_file(port, dict="./", recv_timeout=nil)
      return nil if (ssock = get_srv_sock(port, nil, timeout)).nil?
      return nil if (sock = accept_sock(ssock)).nil?
      if /^PUT_FILE\s+(\S+)\s+(\d+)$/ =~ sock.gets.chop!
        filename, size = File.basename($1), $2
        Dir.mkdir(dit) unless File.exist?(dict)
        filename = File.join(dict, filename)
        open("#{filename}", "wb") do |file|
          file.write(recv_sock(sock))
        end
      end
      debug("receive file: #{filename}, size: #{size}")
      return filename
    end


    private
    #=== Get timeout object for socket.
    #timeout :: timeout seconds
    #returned_value :: timeout object
    def get_socket_timeout(timeout)
      secs = Integer(timeout)
      usecs = Integer((timeout - secs) * 1_000_000)
      timeval = [secs, usecs].pack("l_2")
      return timeval
    end

    #=== Wrapper of accept_sock
    #sock :: Array of Socket object
    #accept_timeout :: Timeout seconds, if nil, wait till connected.
    #returned_value :: A connected socket
    def accept_srv_sock(sock, accept_timeout=nil)
      s = nil
      if accept_timeout
        cnt = 0
        while s.nil? && cnt < accept_timeout
          sock.each do |socket|
            begin
              cnt += DEFAULT_STEP_TIMEOUT
              Timeout::timeout(DEFAULT_STEP_TIMEOUT) do
                s = socket.accept
              end
              return s[0]
            rescue Timeout::Error
            rescue Exception => e
              error("accept failed. #{e.message}")
              error(e.backtrace)
              raise e
            end
          end
        end
        warn("accept failed. Timeout #{accept_timeout} seconds.\n")
        return nil
      else
        while true
          sock.each do |socket|
            begin
              Timeout::timeout(DEFAULT_STEP_TIMEOUT) do
                s = socket.accept
              end
              return s[0]
            rescue Timeout::Error
            rescue Exception => e
              error("accept failed. #{e.message}")
              error(e.backtrace)
              raise e
            end
          end
        end
      end
      return nil
    end
  end
end
