# frozen_string_literal: true

module Capybara::Apparition
  class Browser
    module Frame
      def switch_to_frame(frame)
        case frame
        when Capybara::Node::Base
          current_page.push_frame(frame)
        when :parent
          current_page.pop_frame
        when :top
          current_page.pop_frame(top: true)
        end
      end
    end
  end
end
