# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "lib"
  t.pattern = "test/**/*_test.rb"
  t.verbose = true
end

begin
  require "standard/rake"
rescue LoadError
  # standard not installed
end

task default: %i[test standard]
