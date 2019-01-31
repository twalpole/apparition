# frozen_string_literal: true

module Capybara::Apparition
  class Browser
    module Window
      def window_handle
        @current_page_handle
      end

      def window_handles
        @targets.window_handles
      end

      def switch_to_window(handle)
        target = @targets.get(handle)
        raise NoSuchWindowError unless target&.page

        target.page.wait_for_loaded
        @current_page_handle = handle
      end

      def open_new_window
        context_id = current_target.context_id
        info = command('Target.createTarget', url: 'about:blank', browserContextId: context_id)
        target_id = info['targetId']
        target = DevToolsProtocol::Target.new(self, info.merge('type' => 'page', 'inherit' => current_page))
        target.page # Ensure page object construction happens
        begin
          puts "Adding #{target_id} - #{target.info}" if ENV['DEBUG']
          @targets.add(target_id, target)
        rescue ArgumentError
          puts 'Target already existed' if ENV['DEBUG']
        end
        target_id
      end

      def close_window(handle)
        @current_page_handle = nil if @current_page_handle == handle
        win_target = @targets.delete(handle)
        warn 'Window was already closed unexpectedly' if win_target.nil?
        win_target&.close
      end

      def within_window(locator)
        original = window_handle
        handle = find_window_handle(locator)
        switch_to_window(handle)
        yield
      ensure
        switch_to_window(original)
      end
    end

  private

    def find_window_handle(locator)
      return locator if window_handles.include? locator

      window_handles.each do |handle|
        switch_to_window(handle)
        return handle if evaluate('window.name') == locator
      end
      raise NoSuchWindowError
    end
  end
end
