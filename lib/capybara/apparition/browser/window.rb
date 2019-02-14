# frozen_string_literal: true

module Capybara::Apparition
  class Browser
    module Window
      def current_window_handle
        @current_page_handle
      end

      def window_handles
        page_ids
      end

      def switch_to_window(handle)
        page = @pages[handle]
        unless page
          page = @pages[find_window_handle(handle)]
          warn 'Finding window by name, title, or url is deprecated, please use a block/proc ' \
               'with Session#within_window/Session#switch_to_window instead.'
        end
        raise NoSuchWindowError unless page

        page.wait_for_loaded
        @current_page_handle = page.target_id
      end

      def open_new_window
        context_id = current_page.browser_context_id
        target_id = command('Target.createTarget', url: 'about:blank', browserContextId: context_id)['targetId']
        while !@pages[target_id]
          sleep 0.05
        end

        @pages[target_id].inherit(current_page(allow_nil: true)).send(:main_frame).loaded!
        puts "Set to loaded for target #{target_id} main frame" if ENV['DEBUG']
        target_id
      end

      def close_window(handle)
        @current_page_handle = nil if @current_page_handle == handle
        page = @pages.delete(handle)

        warn 'Window was already closed unexpectedly' unless page
        command('Target.closeTarget', targetId: handle)
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
