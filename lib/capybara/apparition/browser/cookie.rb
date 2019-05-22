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
        current_page.command('Network.getAllCookies')['cookies'].map do |c|
          Capybara::Apparition::Cookie.new(c)
        end
      end

      def set_cookie(cookie)
        cookie[:expires] = cookie[:expires].to_i if cookie[:expires]

        current_page.command('Network.setCookie', cookie)
      end

      def remove_cookie(name)
        current_page.command('Network.deleteCookies', name: name, url: current_url)
      end

      def clear_cookies
        current_page.command('Network.clearBrowserCookies')
      end

      def cookies_enabled=(flag)
        current_page.command('Emulation.setDocumentCookieDisabled', disabled: !flag)
      end
    end
  end
end
