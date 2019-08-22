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

      alias id session_id
    private
    end
  end
end
