# frozen_string_literal: true

module Capybara::Apparition
  class Mouse
    def initialize(page, keyboard)
      @page = page
      @keyboard = keyboard
      @current_pos = { x: 0, y: 0 }
    end

    def click_at(x:, y:, button: 'left', count: 1, modifiers: [])
      move_to x: x, y: y
      @keyboard.with_keys(modifiers) do
        mouse_params = { x: x, y: y, button: button, count: count }
        down mouse_params
        up mouse_params
      end
      self
    end

    def move_to(x:, y:, **options)
      @current_pos = { x: x, y: y }
      mouse_event('mouseMoved', x: x, y: y, **options)
      self
    end

    def down(**options)
      options = @current_pos.merge(options)
      mouse_event('mousePressed', options)
      self
    end

    def up(**options)
      options = @current_pos.merge(options)
      mouse_event('mouseReleased', options)
      self
    end

  private

    def mouse_event(type, x:, y:, button: 'left', count: 1)
      @page.command('Input.dispatchMouseEvent',
                    type: type,
                    button: button,
                    x: x,
                    y: y,
                    modifiers: @keyboard.modifiers,
                    clickCount: count)
    end
  end
end
