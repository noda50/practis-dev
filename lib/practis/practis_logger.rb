#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'logger'

require 'practis'

module Practis
  class PractisLogger

    ## <<< [2013/08/30 I.Noda]
    ##  log の出力先を複数許すために、追加。
    ##  ただ、引数の並びは気に入らない。
    ##  -> 結局並びを変更
    ## >>> [2013/08/30 I.Noda]
    #def initialize(out=STDERR, level=Logger::DEBUG, *auxLogger)
    #def initialize(out=STDERR, level=Logger::WARN, *auxLoggers)
    def initialize(level=Logger::WARN, out=STDERR, *auxLoggers)
#      @logger = Logger.new(out)
      @loggerList = [Logger.new(out)] ;
      auxLoggers.each{|aux| 
        if(!aux.nil?) then
          log = Logger.new(aux)
          @loggerList.push(log) ;
        end
      }
#      @logger.level = level}
      @loggerList.each{|logger| logger.level = level}
    end

    def set_progname(progname)
#      @logger.progname = progname
      @loggerList.each{|logger| logger.progname = progname}
    end

    def get_progname
#      return @logger.progname
      return @loggerList[0].progname
    end

    def fatal(str, *args)
      string, filename, linenum, function = get_string_file_line(str, *args)
#      @logger.fatal("#{filename}:#{linenum}:#{function}, #{string}")
      msg = "#{filename}:#{linenum}:#{function}, #{string}";
      @loggerList.each{|logger| logger.fatal(msg)}
    end

    def error(str, *args)
      string, filename, linenum, function = get_string_file_line(str, *args)
#      @logger.error("#{filename}:#{linenum}:#{function}, #{string}")
      msg = "#{filename}:#{linenum}:#{function}, #{string}";
      @loggerList.each{|logger| logger.error(msg)}
    end

    def warn(str, *args)
      string, filename, linenum, function = get_string_file_line(str, *args)
#      @logger.warn("#{filename}:#{linenum}:#{function}, #{string}")
      msg = "#{filename}:#{linenum}:#{function}, #{string}";
      @loggerList.each{|logger| logger.warn(msg)}
    end

    def info(str, *args)
      string, filename, linenum, function = get_string_file_line(str, *args)
#      @logger.info("#{filename}:#{linenum}:#{function}, #{string}")
      msg = "#{filename}:#{linenum}:#{function}, #{string}";
      @loggerList.each{|logger| logger.info(msg)}
    end

    def debug(str, *args)
      string, filename, linenum, function = get_string_file_line(str, *args)
#      @logger.debug("#{filename}:#{linenum}:#{function}, #{string}")
      msg = "#{filename}:#{linenum}:#{function}, #{string}";
      @loggerList.each{|logger| logger.debug(msg)}
    end

    private
    def get_string_file_line(str, *args)
      begin
        string = sprintf(str, *args)
        caller()[2] =~ /(.*?):(\d+)(:in `(.*)')?/
        filename, linenum, function = $1, $2, $3
        filename = File.basename(filename)
        return string, filename, linenum, function
      rescue Exception => e
        @loggerList.each{|logger|
          logger.error("fail to get filename, line, function. #{e.message}")
          logger.error(e.backtrace)
        }
        return nil, nil, nil, nil
      end
    end
  end
end
