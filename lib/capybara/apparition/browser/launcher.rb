require 'capybara/apparition/browser/launcher/local'

module Capybara::Apparition
  class Browser
    class Launcher
      def self.start(options)
        browser_options = options.fetch(:browser_options, {})

        Local.start(
          headless: options.fetch(:headless, true),
          browser_options: browser_options
        )
      end
    end
  end
end