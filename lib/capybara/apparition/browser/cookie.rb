# frozen_string_literal: true

require 'capybara/apparition/cookie_jar'

module Capybara::Apparition
  class Browser
    module Cookie
      def cookies
        CookieJar.new(
          # current_page.command('Network.getCookies')['cookies'].map { |c| Cookie.new(c) }
          self
        )
      end

      def all_cookies
        CookieJar.new(
          # current_page.command('Network.getAllCookies')['cookies'].map { |c| Cookie.new(c) }
          self
        )
      end

      def get_raw_cookies
        current_page.command('Network.getAllCookies')['cookies'].map do |c|
          Capybara::Apparition::Cookie.new(c)
        end
      end

      def set_cookie(cookie)
        if cookie[:expires]
          # cookie[:expires] = cookie[:expires].to_i * 1000
          cookie[:expires] = cookie[:expires].to_i
        end

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
