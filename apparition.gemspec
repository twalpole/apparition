lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'capybara/apparition/version'

Gem::Specification.new do |s|
  s.name          = 'apparition'
  s.version       = Capybara::Apparition::VERSION
  s.platform      = Gem::Platform::RUBY
  s.authors       = ['Thomas Walpole']
  s.email         = ['twalpole@gmail.com']
  s.homepage      = 'https://github.com/twalpole/apparition'
  s.summary       = 'Chrome driver for Capybara'
  s.description   = 'Apparition is a driver for Capybara that allows you to '\
                    'run your tests on Chrome'
  s.license       = 'MIT'
  s.require_paths = ['lib']
  s.files         = Dir.glob('{lib}/**/*') + %w(LICENSE README.md)

  s.required_ruby_version = '>= 2.2.2'

  s.add_runtime_dependency 'capybara',         '~> 2.1'
  s.add_runtime_dependency 'cliver',           '~> 0.3.1'
  s.add_runtime_dependency 'chrome_remote'

  s.add_development_dependency 'launchy',            '~> 2.0'
  s.add_development_dependency 'rspec',              '~> 3.6.0'
  s.add_development_dependency 'sinatra',            '~> 2.0'
  s.add_development_dependency 'rake'
  s.add_development_dependency 'image_size',         '~> 1.0'
  s.add_development_dependency 'pdf-reader',         '~> 1.3', '>= 1.3.3'
  s.add_development_dependency 'erubi'  # required by rbx
  s.add_development_dependency 'os'  # required by rbx
  s.add_development_dependency 'byebug'
end
