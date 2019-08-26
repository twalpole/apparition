# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

gem 'capybara'

if RUBY_ENGINE == 'jruby'
  # nio4r <= 2.4.0 used by puma 4.x has a bug with JRuby - use puma 3.x for now
  gem 'puma', '~>3.0'
else
  gem 'puma'
end
