# frozen_string_literal: true

require 'capybara/apparition/browser/launcher/local'
require 'capybara/apparition/browser/launcher/remote'

module Capybara::Apparition
  class Browser
    class Launcher
      def self.start(options)
        browser_options = options.fetch(:browser_options, {})

        if options.fetch(:remote, false)
          Remote.start(
            browser_options
          )
        else
          Local.start(
            headless: options.fetch(:headless, true),
            browser_options: browser_options
          )
        end
      end
    end
  end
end
