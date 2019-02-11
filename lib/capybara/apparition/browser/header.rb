# frozen_string_literal: true

module Capybara::Apparition
  class Browser
    module Header
      def headers
        current_page.extra_headers
      end

      def headers=(headers)
        @pages.each do |_id, page|
          page.perm_headers = headers.dup
          page.temp_headers = {}
          page.temp_no_redirect_headers = {}
          page.update_headers
        end
      end

      def add_headers(headers)
        current_page.perm_headers.merge! headers
        current_page.update_headers
      end

      def add_header(header, permanent: true, **_options)
        if permanent == true
          @pages.each do |_id, page|
            page.perm_headers.merge! header
            page.update_headers
          end
        else
          if permanent.to_s == 'no_redirect'
            current_page.temp_no_redirect_headers.merge! header
          else
            current_page.temp_headers.merge! header
          end
          current_page.update_headers
        end
      end
    end
  end
end
