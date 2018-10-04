# frozen_string_literal: true

require 'bundler/setup'
require 'rspec/core/rake_task'

require 'capybara/apparition/version'

RSpec::Core::RakeTask.new('test')
task default: %i[test]

task :release do
  version = Capybara::Apparition::VERSION
  puts "Releasing #{version}, y/n?"
  exit(1) unless STDIN.gets.chomp == 'y'
  sh 'gem build apparition.gemspec && ' \
     "gem push apparition-#{version}.gem && " \
     "git tag v#{version} && " \
     'git push --tags'
end
