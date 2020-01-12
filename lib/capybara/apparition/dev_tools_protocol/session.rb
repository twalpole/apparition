# frozen_string_literal: true

module Capybara::Apparition
  module DevToolsProtocol
    class Session
      attr_reader :browser, :connection, :session_id

      def initialize(browser, connection, session_id)
        @browser = browser
        @connection = connection
        @session_id = session_id
        @handlers = []
      end

      def command(name, **params)
        send_cmd(name, params).result
      end

      def commands(*names)
        responses = names.map { |name| send_cmd(name) }
        responses.map(&:result)
      end

      def async_command(name, **params)
        send_cmd(name, **params).discard_result
      end

      def async_commands(*names)
        names.map { |name| async_command(name) }
      end

      def on(event_name, &block)
        connection.on(event_name, @session_id, &block)
      end

    private

      def send_cmd(name, **params)
        @browser.command_for_session(@session_id, name, params)
      end
    end
  end
end
