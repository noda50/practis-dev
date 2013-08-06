#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'logger'

require 'practis'

module Practis
  class PractisLogger

    #def initialize(out=STDERR, level=Logger::DEBUG)
    def initialize(out=STDERR, level=Logger::WARN)
      @logger = Logger.new(out)
      @logger.level = level
    end

    def set_progname(progname)
      @logger.progname = progname
    end

    def get_progname
      return @logger.progname
    end

    def fatal(str, *args)
      string, filename, linenum, function = get_string_file_line(str, *args)
      @logger.fatal("#{filename}:#{linenum}:#{function}, #{string}")
    end

    def error(str, *args)
      string, filename, linenum, function = get_string_file_line(str, *args)
      @logger.error("#{filename}:#{linenum}:#{function}, #{string}")
    end

    def warn(str, *args)
      string, filename, linenum, function = get_string_file_line(str, *args)
      @logger.warn("#{filename}:#{linenum}:#{function}, #{string}")
    end

    def info(str, *args)
      string, filename, linenum, function = get_string_file_line(str, *args)
      @logger.info("#{filename}:#{linenum}:#{function}, #{string}")
    end

    def debug(str, *args)
      string, filename, linenum, function = get_string_file_line(str, *args)
      @logger.debug("#{filename}:#{linenum}:#{function}, #{string}")
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
        @logger.error("fail to get filename, line, function. #{e.message}")
        @logger.error(e.backtrace)
        return nil, nil, nil, nil
      end
    end
  end
end
