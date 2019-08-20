# frozen_string_literal: true

require 'capybara/apparition/cookie_jar'

module Capybara::Apparition
  class Browser
    module Cookie
      def cookies
        CookieJar.new(self)
      end
      alias :all_cookies :cookies

      def get_raw_cookies
        current_page.session.connection.network.get_all_cookies(_session_id: current_page.session.id)[:cookies].map do |c|
          Capybara::Apparition::Cookie.new(c)
        end
      end

      def set_cookie(cookie)
        cookie[:expires] = cookie[:expires].to_i if cookie[:expires]

        current_page.session.connection.network.set_cookie(_session_id: current_page.session.id, **cookie).result
      end

      def remove_cookie(name)
        current_page.session.connection.network.delete_cookies(_session_id: current_page.session.id, name: name, url: current_url).result
      end

      def clear_cookies
        current_page.session.connection.network.clear_browser_cookies(_session_id: current_page.session.id).result
      end

      def cookies_enabled=(flag)
        current_page.session.connection.emulation.set_document_cookie_disabled(_session_id: current_page.session.id, disabled: !flag).result
      end
    end
  end
end
