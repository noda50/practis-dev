#!/usr/bin/ruby
# -*- coding: utf-8 -*-

module Practis
  VERSION = "0.0.1"
  VERSION_ARRAY = VERSION.split(/\./).map {|x| x.to_i}
  VERSION_MAJOR = VERSION_ARRAY[0]
  VERSION_MINER = VERSION_ARRAY[1]
  VERSION_BUILD = VERSION_ARRAY[2]
end
