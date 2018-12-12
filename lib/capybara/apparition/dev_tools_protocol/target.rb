# frozen_string_literal: true

require 'capybara/apparition/dev_tools_protocol/session'

module Capybara::Apparition
  module DevToolsProtocol
    class Target
      attr_accessor :info

      def initialize(browser, info)
        @browser = browser
        @page = nil
        @info = info
      end

      def id
        info['targetId']
      end

      def title
        info['title']
      end

      def url
        info['url']
      end

      def page
        if !@page && info['type'] == 'page'
          @session = create_session
          @page = Page.create(@browser, @session, id, true, nil)
        end
        @page
      end

      def close
        # @browser.command("Target.detachFromTarget", sessionId: @session.session_id)
        @browser.command("Target.closeTarget", targetId: id)
      end

    private

      def create_session
        session_id = @browser.command('Target.attachToTarget', targetId: id)['sessionId']
        Session.new(@browser, @browser.client, id, session_id)
      end
    end
  end
end
