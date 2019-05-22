module Capybara::Apparition
  class Browser
    class PageManager
      def initialize(browser)
        @browser = browser
        @pages = {}
      end

      def ids
        @pages.keys
      end

      def [](id)
        @pages[id]
      end

      def each(&block)
        @pages.each_value(&block)
      end

      def reset
        @pages.each do |id, page|
          begin
            @browser.client.send_cmd('Target.disposeBrowserContext', browserContextId: page.browser_context_id).discard_result
          rescue WrongWorld
            puts 'Unknown browserContextId'
          end
          @pages.delete(id)
        end
      end

      def create(id, session, ctx_id, **options)
        @pages[id] = Page.create(@browser, session, id, ctx_id, **options)
      end

      def delete(id)
        @pages.delete(id)
      end

      def refresh(opener:, **page_options)
        new_pages = @browser.command('Target.getTargets')['targetInfos'].select do |ti|
          (ti['openerId'] == opener.target_id) && (ti['type'] == 'page') && (ti['attached'] == false)
        end

        sessions = new_pages.map do |page|
          target_id = page['targetId']
          session_result = @browser.client.send_cmd('Target.attachToTarget', targetId: target_id)
          [target_id, session_result]
        end

        sessions = sessions.map do |(target_id, session_result)|
          session = Capybara::Apparition::DevToolsProtocol::Session.new(@browser, @browser.client, session_result.result['sessionId'])
          [target_id, session]
        end

        sessions.each do |(_id, session)|
          session.async_commands 'Page.enable', 'Network.enable', 'Runtime.enable', 'Security.enable', 'DOM.enable'
        end

        sessions.each do |(target_id, session)|
          new_page = Page.create(@browser, session, target_id, opener.browser_context_id, page_options).inherit(opener)
          @pages[target_id] = new_page
        end
      end

      def whitelist=(list)
        @pages.each_value { |page| page.url_whitelist = list}
      end

      def blacklist=(list)
        @pages.each_value { |page| page.url_blacklist = list}
      end
    end
  end
end

