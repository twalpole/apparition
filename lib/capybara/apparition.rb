# frozen_string_literal: true

require 'backports/2.4.0/enumerable/sum'
require 'backports/2.4.0/string/match'
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
  Capybara::Apparition::Driver.new(app, headless: true)
end
