# frozen_string_literal: true

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
