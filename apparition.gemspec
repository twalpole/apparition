# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)

require 'capybara/apparition/version'

Gem::Specification.new do |s|
  s.name          = 'apparition'
  s.version       = Capybara::Apparition::VERSION
  s.platform      = Gem::Platform::RUBY
  s.authors       = ['Thomas Walpole']
  s.email         = ['twalpole@gmail.com']
  s.homepage      = 'https://github.com/twalpole/apparition'
  s.summary       = 'Chrome driver using CDP for Capybara'
  s.description   = 'Apparition is a driver for Capybara that allows you to ' \
                    'run your tests on Chrome in a headless or headed manner'
  s.license       = 'MIT'
  s.require_paths = ['lib']
  s.files         = Dir.glob('{lib}/**/*') + %w[LICENSE README.md]

  s.required_ruby_version = '>= 2.4.0'

  s.add_runtime_dependency 'capybara', '~> 3.13', '< 4'
  s.add_runtime_dependency 'websocket-driver', '>=0.6.5'

  s.add_development_dependency 'byebug'
  s.add_development_dependency 'chunky_png'
  s.add_development_dependency 'fastimage'
  s.add_development_dependency 'irb'
  s.add_development_dependency 'launchy', '~> 2.0'
  s.add_development_dependency 'os'
  s.add_development_dependency 'pdf-reader', '>= 1.3.3'
  s.add_development_dependency 'rake'
  s.add_development_dependency 'rspec', '~> 3.6'
  s.add_development_dependency 'rubocop'
  s.add_development_dependency 'rubocop-performance'
  s.add_development_dependency 'rubocop-rspec'
  s.add_development_dependency 'selenium-webdriver'
  s.add_development_dependency 'sinatra', '~> 2.0'
end
