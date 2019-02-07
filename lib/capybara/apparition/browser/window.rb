# frozen_string_literal: true

module Capybara::Apparition
  class Browser
    module Window
      def current_window_handle
        @current_page_handle
      end

      def window_handles
        @targets.window_handles
      end

      def switch_to_window(handle)
        target = @targets.get(handle)
        unless target&.page
          target = @targets.get(find_window_handle(handle))
          warn 'Finding window by name, title, or url is deprecated, please use a block/proc ' \
               'with Session#within_window/Session#switch_to_window instead.'
        end
        raise NoSuchWindowError unless target&.page

        target.page.wait_for_loaded
        @current_page_handle = target.id
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
    end

  private

    def find_window_handle(locator)
      original = current_window_handle
      return locator if window_handles.include? locator

      window_handles.each do |handle|
        switch_to_window(handle)
        return handle if evaluate('[window.name, document.title, window.location.href]').include? locator
      end
      raise NoSuchWindowError
    ensure
      switch_to_window(original) if original
    end
  end
end
