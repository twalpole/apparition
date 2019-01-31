# frozen_string_literal: true

module Capybara::Apparition
  class Browser
    module Auth
      def set_proxy_auth(user, password)
        set_auth(:proxy, user, password)
      end

      def set_http_auth(user, password)
        set_auth(:http, user, password)
      end

    private

      def set_auth(type, user, password)
        creds = user.nil? && password.nil? ? nil : { username: user, password: password }

        case type
        when :http
          current_page.credentials = creds
        when :proxy
          @proxy_auth = creds
        end
      end
    end
  end
end
