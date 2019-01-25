# frozen_string_literal: true

require 'capybara/apparition/dev_tools_protocol/session'

module Capybara::Apparition
  module DevToolsProtocol
    class Target
      attr_accessor :info

      def initialize(browser, info)
        @browser = browser
        @info = info
        @page = nil
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
        @page ||= begin
          if info['type'] == 'page'
            Page.create(@browser, create_session, id,
                        ignore_https_errors: @browser.ignore_https_errors,
                        js_errors: @browser.js_errors).inherit(info.delete('inherit'))
          else
            nil
          end
        end
      end

      def close
        @browser.command('Target.closeTarget', targetId: id)
      end

    private

      def create_session
        session_id = @browser.command('Target.attachToTarget', targetId: id)['sessionId']
        Session.new(@browser, @browser.client, id, session_id)
      end
    end
  end
end
