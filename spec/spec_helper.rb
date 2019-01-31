# frozen_string_literal: true

APPARITION_ROOT = File.expand_path('..', __dir__)
$LOAD_PATH.unshift(APPARITION_ROOT + '/lib')

require 'bundler/setup'
require 'byebug'
require 'rspec'
require 'capybara/spec/spec_helper'
require 'capybara/apparition'

require 'support/test_app'
require 'support/spec_logger'
require 'support/capybara-webkit/app_runner'
require 'support/capybara-webkit/output_writer'

Capybara.register_driver :apparition do |app|
  debug = !ENV['DEBUG'].nil?
  options = {
    logger: TestSessions.logger,
    inspector: debug,
    debug: debug,
    headless: true
  }

  Capybara::Apparition::Driver.new(
    app, options
  )
end

module TestSessions
  def self.logger
    @logger ||= SpecLogger.new
  end

  Apparition = Capybara::Session.new(:apparition, TestApp)
end

RSpec::Expectations.configuration.warn_about_potential_false_positives = false if ENV['TRAVIS']

RSpec.configure do |config|
  config.before do
    TestSessions.logger.reset
  end

  config.filter_run_including focus: true unless ENV['TRAVIS']
  config.filter_run_excluding selenium_compatibility: ENV['TRAVIS']
  config.run_all_when_everything_filtered = true

  config.include Capybara::RSpecMatchers

  config.after do |example|
    if ENV['DEBUG'] || (ENV['TRAVIS'] && example.exception)
      puts TestSessions.logger.messages
    end
  end

  Capybara::SpecHelper.configure(config)

  config.before do
    # This is not technically correct since it runs a number of Capybara tests
    # with incorrect timing.
    # TODO: remove this override when all tests passing
    Capybara.default_max_wait_time = 0
    # Capybara.default_max_wait_time = 1
  end

  %i[js modals windows].each do |cond|
    config.before(:each, requires: cond) do
      Capybara.default_max_wait_time = 1
    end
  end
end
