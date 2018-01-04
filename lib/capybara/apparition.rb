if RUBY_VERSION < "2.2.2"
  raise "This version of Capybara/Apparition does not support Ruby versions " \
        "less than 2.2.2."
end

require 'capybara'

module Capybara
  module Apparition
    require 'capybara/apparition/utility'
    require 'capybara/apparition/driver'
    require 'capybara/apparition/browser'
    require 'capybara/apparition/node'
    require 'capybara/apparition/inspector'
    require 'capybara/apparition/network_traffic'
    require 'capybara/apparition/errors'
    require 'capybara/apparition/cookie'
  end
end

Capybara.register_driver :apparition do |app|
  Capybara::Apparition::Driver.new(app)
end
