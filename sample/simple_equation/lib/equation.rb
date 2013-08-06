#!/usr/bin/env ruby
# -*- coding: utf-8 -*-


module Equation

  class SimpleEquation

    def initialize(a, b)
      @a = a
      @b = b
    end

    def examine
      return Math.exp(-(@a**2 + @b**2))
    end
  end
end
