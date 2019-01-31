# frozen_string_literal: true

module Capybara::Apparition
  class Browser
    module Modal
      def accept_alert
        current_page.add_modal(alert: true)
      end

      def accept_confirm
        current_page.add_modal(confirm: true)
      end

      def dismiss_confirm
        current_page.add_modal(confirm: false)
      end

      def accept_prompt(response)
        current_page.add_modal(prompt: response)
      end

      def dismiss_prompt
        current_page.add_modal(prompt: false)
      end

      def modal_message
        current_page.modal_messages.shift
      end
    end
  end
end
