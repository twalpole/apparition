# frozen_string_literal: true

module Capybara::Apparition
  class Mouse
    def initialize(page, keyboard)
      @page = page
      @keyboard = keyboard
    end

    def click_at(x:, y:, button: 'left', count: 1, modifiers: [])
      move_to(x: x, y: y)
      @keyboard.yield_with_keys(modifiers) do
        down(x: x, y: y, button: button, count: count)
        up(x: x, y: y, button: button, count: count)
      end
    end

    def move_to(x:, y:, button: 'none')
      @page.command('Input.dispatchMouseEvent',
                    type: 'mouseMoved',
                    button: button,
                    x: x,
                    y: y,
                    modifiers: @keyboard.modifiers)
    end

    def down(x:, y:, button: 'left', count: 1)
      @page.command('Input.dispatchMouseEvent',
                    type: 'mousePressed',
                    button: button,
                    x: x,
                    y: y,
                    modifiers: @keyboard.modifiers,
                    clickCount: count)
    end

    def up(x:, y:, button: 'left', count: 1)
      @page.command('Input.dispatchMouseEvent',
                    type: 'mouseReleased',
                    button: button,
                    x: x,
                    y: y,
                    modifiers: @keyboard.modifiers,
                    clickCount: count)
    end
  end
end
