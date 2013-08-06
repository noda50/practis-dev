#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'practis'

module Practis

  #=== Store current executable.
  class ExecutableGroup

    include Practis

    def initialize
      @threads = ThreadGroup.new
    end

    def exec(*args)
      th = Thread.start do
        fork_exec(*args)
      end
      @threads.add(th)
    end

    def fork_exec(*args)
      if pid = fork
        Process.waitpid(pid)
      else
        Kernel.exec(*args)
      end
    end

    def wait
      @threads.list.each do |th|
        th.join
      end
    end

    def update
      @threads.list.each { |th| th.join unless th.alive? }
    end

    def length
      return @threads.list.length
    end
  end
end

