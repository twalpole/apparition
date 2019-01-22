# frozen_string_literal: true

module Capybara::Apparition
  module DevToolsProtocol
    class Session
      attr_reader :browser, :connection, :target_id, :session_id, :handlers

      def initialize(browser, connection, target_id, session_id)
        @browser = browser
        @connection = connection
        @target_id = target_id
        @session_id = session_id
        @handlers = []
      end

      def command(name, **params)
        @browser.command_for_session(@session_id, name, params, async: false)
      end

      def async_command(name, **params)
        @browser.command_for_session(@session_id, name, params, async: true)
      end

      def on(event_name, &block)
        connection.on(event_name, @session_id, &block)
      end
    end
  end
end
