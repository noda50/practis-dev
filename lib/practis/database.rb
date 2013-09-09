#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'rubygems'

require 'practis'

module Practis
  module Database

    # Constants

    FIELD_ATTRS = %w(field type null key default extra comment)
    FIELD_KEYS = %w(PRI UNI MUL) << ""
    FIELD_INDEXED = {"key" => "MUL"}
  end
end
