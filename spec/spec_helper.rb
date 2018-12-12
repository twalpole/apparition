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

Capybara.register_driver :apparition do |app|
  debug = !ENV['DEBUG'].nil?
  options = {
    logger: TestSessions.logger,
    inspector: debug,
    debug: debug
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

module Apparition
  module SpecHelper
    class << self
      def set_capybara_wait_time(time)
        Capybara.default_max_wait_time = time
      end
    end
  end
end

RSpec::Expectations.configuration.warn_about_potential_false_positives = false if ENV['TRAVIS']

RSpec.configure do |config|
  config.before do
    TestSessions.logger.reset
  end

  # config.filter_run_including focus: true unless ENV['TRAVIS']
  config.run_all_when_everything_filtered = true

  config.include Capybara::RSpecMatchers

  config.after do |example|
    if ENV['DEBUG']
      puts TestSessions.logger.messages
    elsif ENV['TRAVIS'] && example.exception
      example.exception.message << "\n\nDebug info:\n" + TestSessions.logger.messages.join("\n")
    end
  end

  Capybara::SpecHelper.configure(config)

  config.filter_run_excluding full_description: lambda { |description, _metadata|
    # test is marked pending in Capybara but Apparition passes - disable here - have our own test in driver spec
    description =~ /Capybara::Session Apparition node #set should allow me to change the contents of a contenteditable elements child/ ||
      # The Capybara provided size tests query outerWidth/Height we use inner - have our own tests in session spec
      description =~ /Capybara::Session Apparition Capybara::Window#size should return size of whole window/ ||
      description =~ /Capybara::Session Apparition Capybara::Window#size should switch to original window if invoked not for current window/
  }

  config.before do
    # Apparition::SpecHelper.set_capybara_wait_time(0)
    Apparition::SpecHelper.set_capybara_wait_time(1)
  end

  %i[js modals windows].each do |cond|
    config.before(:each, requires: cond) do
      Apparition::SpecHelper.set_capybara_wait_time(1)
    end
  end
end

require 'rspec/retry'
RSpec.configure do |config|
  # show retry status in spec process
  config.verbose_retry = true
  # show exception that triggers a retry if verbose_retry is set to true
  config.display_try_failure_messages = true
  config.default_retry_count = 3

  config.around :each do |ex|
    ex.run_with_retry retry: 1
  end
end


