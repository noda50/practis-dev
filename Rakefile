require 'rubygems'

#
# Tests
#
require 'rake/testtask'

Rake::TestTask.new do |test|
  test.verbose = true
  test.libs << "test"
  test.libs << "lib"
  test.test_files = FileList['test/**/test_*.rb']
end
task :default => :test

#
# Document
#
require 'rdoc/task'

Rake::RDocTask.new do |rd|
  rd.rdoc_dir = 'rdoc'
  rd.rdoc_files = FileList["lib/**/*.rb"]
  rd.options << '-charset=UTF-8 '
end
