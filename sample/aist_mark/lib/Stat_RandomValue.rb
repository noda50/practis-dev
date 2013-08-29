#! /usr/bin/env ruby
## -*- Mode: ruby -*-
##Header:
##Title: Random Value Base
##Author: Itsuki Noda
##Date: 2006/06/21
##EndHeader:

##======================================================================
module Stat
  class RandomValue
    ##------------------------------
    def value()
      raise "RandomValue\$value() is not implemented for : " + self.class.name ;
    end

    ##------------------------------
    def to_s()
      "\#<#{self.class.name()}>" ;
    end


  end

end
