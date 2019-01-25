# frozen_string_literal: true

module Capybara::Apparition
  class Keyboard
    attr_reader :modifiers

    def initialize(page)
      @page = page
      @modifiers = 0
      @pressed_keys = {}
    end

    def type(keys)
      type_with_modifiers(Array(keys))
    end

    def press(key)
      if key.is_a? Symbol
        orig_key = key
        key = key.to_s.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase.to_sym
        warn "The use of :#{orig_key} is deprecated, please use :#{key} instead" unless key == orig_key
      end
      description = key_description(key)
      down(description)
      up(description) if modifier_bit(description.key).zero?
    end

    def down(description)
      @modifiers |= modifier_bit(description.key)
      @pressed_keys[description.key] = description

      @page.command('Input.dispatchKeyEvent',
                    type: 'keyDown',
                    modifiers: @modifiers,
                    windowsVirtualKeyCode: description.keyCode,
                    code: description.code,
                    key: description.key,
                    text: description.text,
                    unmodifiedText: description.text,
                    autoRepeat: false,
                    location: description.location,
                    isKeypad: description.location == 3)
    end

    def up(description)
      @modifiers &= ~modifier_bit(description.key)
      @pressed_keys.delete(description.key)

      @page.command('Input.dispatchKeyEvent',
                    type: 'keyUp',
                    modifiers: @modifiers,
                    key: description.key,
                    windowsVirtualKeyCode: description.keyCode,
                    code: description.code,
                    location: description.location)
    end

    def yield_with_keys(keys = [])
      old_pressed_keys = @pressed_keys
      @pressed_keys = {}
      keys.each do |key|
        press key
      end
      yield
      release_pressed_keys
      @pressed_keys = old_pressed_keys
    end

  private

    def type_with_modifiers(keys)
      keys = Array(keys)
      old_pressed_keys = @pressed_keys
      @pressed_keys = {}

      keys.each do |sequence|
        if sequence.is_a? Array
          type_with_modifiers(sequence)
        elsif sequence.is_a? String
          sequence.each_char { |char| press char }
        else
          press sequence
        end
      end

      release_pressed_keys
      @pressed_keys = old_pressed_keys

      true
    end

    def release_pressed_keys
      @pressed_keys.values.each { |desc| up(desc) }
    end

    def key_description(key)
      shift = (@modifiers & 8).nonzero?
      description = OpenStruct.new(
        key: '',
        keyCode: 0,
        code: '',
        text: '',
        location: 0
      )

      definition = KEY_DEFINITIONS[key.to_sym]
      raise KeyError, "Unknown key: #{key}" if definition.nil?

      definition = OpenStruct.new definition

      description.key = definition.key if definition.key
      description.key = definition.shiftKey if shift && definition.shiftKey

      description.keyCode = definition.keyCode if definition.keyCode
      description.keyCode = definition.shiftKeyCode if shift && definition.shiftKeyCode

      description.code = definition.code if definition.code

      description.location = definition.location if definition.location

      description.text = description.key if description.key.length == 1
      description.text = definition.text if definition.text
      description.text = definition.shiftText if shift && definition.shiftText

      # if any modifiers besides shift are pressed, no text should be sent
      description.text = '' if (@modifiers & ~8).nonzero?

      description
    end

    def modifier_bit(key)
      case key
      when 'Alt' then 1
      when 'Control' then 2
      when 'Meta' then 4
      when 'Shift' then 8
      else
        0
      end
    end

    # /**
    #  * @typedef {Object} KeyDefinition
    #  * @property {number=} keyCode
    #  * @property {number=} shiftKeyCode
    #  * @property {string=} key
    #  * @property {string=} shiftKey
    #  * @property {string=} code
    #  * @property {string=} text
    #  * @property {string=} shiftText
    #  * @property {number=} location
    #  */

    # rubocop:disable Metrics/LineLength
    KEY_DEFINITIONS = {
      '0': { 'keyCode': 48, 'key': '0', 'code': 'Digit0' },
      '1': { 'keyCode': 49, 'key': '1', 'code': 'Digit1' },
      '2': { 'keyCode': 50, 'key': '2', 'code': 'Digit2' },
      '3': { 'keyCode': 51, 'key': '3', 'code': 'Digit3' },
      '4': { 'keyCode': 52, 'key': '4', 'code': 'Digit4' },
      '5': { 'keyCode': 53, 'key': '5', 'code': 'Digit5' },
      '6': { 'keyCode': 54, 'key': '6', 'code': 'Digit6' },
      '7': { 'keyCode': 55, 'key': '7', 'code': 'Digit7' },
      '8': { 'keyCode': 56, 'key': '8', 'code': 'Digit8' },
      '9': { 'keyCode': 57, 'key': '9', 'code': 'Digit9' },
      # 'numpad0': { 'keyCode': 45, 'shiftKeyCode': 96, 'key': 'Insert', 'code': 'Numpad0', 'shiftKey': '0', 'location': 3 },
      # 'numpad1': { 'keyCode': 35, 'shiftKeyCode': 97, 'key': 'End', 'code': 'Numpad1', 'shiftKey': '1', 'location': 3 },
      # 'numpad2': { 'keyCode': 40, 'shiftKeyCode': 98, 'key': 'ArrowDown', 'code': 'Numpad2', 'shiftKey': '2', 'location': 3 },
      # 'numpad3': { 'keyCode': 34, 'shiftKeyCode': 99, 'key': 'PageDown', 'code': 'Numpad3', 'shiftKey': '3', 'location': 3 },
      # 'numpad4': { 'keyCode': 37, 'shiftKeyCode': 100, 'key': 'ArrowLeft', 'code': 'Numpad4', 'shiftKey': '4', 'location': 3 },
      # 'numpad5': { 'keyCode': 12, 'shiftKeyCode': 101, 'key': 'Clear', 'code': 'Numpad5', 'shiftKey': '5', 'location': 3 },
      # 'numpad6': { 'keyCode': 39, 'shiftKeyCode': 102, 'key': 'ArrowRight', 'code': 'Numpad6', 'shiftKey': '6', 'location': 3 },
      # 'numpad7': { 'keyCode': 36, 'shiftKeyCode': 103, 'key': 'Home', 'code': 'Numpad7', 'shiftKey': '7', 'location': 3 },
      # 'numpad8': { 'keyCode': 38, 'shiftKeyCode': 104, 'key': 'ArrowUp', 'code': 'Numpad8', 'shiftKey': '8', 'location': 3 },
      # 'numpad9': { 'keyCode': 33, 'shiftKeyCode': 105, 'key': 'PageUp', 'code': 'Numpad9', 'shiftKey': '9', 'location': 3 },
      # 'multiply': { 'keyCode': 106, 'code': 'NumpadMultiply', 'key': '*', 'location': 3 },
      # 'add': { 'keyCode': 107, 'code': 'NumpadAdd', 'key': '+', 'location': 3 },
      # 'subtract': { 'keyCode': 109, 'code': 'NumpadSubtract', 'key': '-', 'location': 3 },
      # 'divide': { 'keyCode': 111, 'code': 'NumpadDivide', 'key': '/', 'location': 3 },
      'numpad0': { 'keyCode': 96, 'code': 'Numpad0', 'key': '0', 'location': 3 },
      'numpad1': { 'keyCode': 97, 'code': 'Numpad1', 'key': '1', 'location': 3 },
      'numpad2': { 'keyCode': 98, 'code': 'Numpad2', 'key': '2', 'location': 3 },
      'numpad3': { 'keyCode': 99, 'code': 'Numpad3', 'key': '3', 'location': 3 },
      'numpad4': { 'keyCode': 100, 'code': 'Numpad4', 'key': '4', 'location': 3 },
      'numpad5': { 'keyCode': 101, 'code': 'Numpad5', 'key': '5', 'location': 3 },
      'numpad6': { 'keyCode': 102, 'code': 'Numpad6', 'key': '6', 'location': 3 },
      'numpad7': { 'keyCode': 103, 'code': 'Numpad7', 'key': '7', 'location': 3 },
      'numpad8': { 'keyCode': 104, 'code': 'Numpad8', 'key': '8', 'location': 3 },
      'numpad9': { 'keyCode': 104, 'code': 'Numpad9', 'key': '9', 'location': 3 },
      'multiply': { 'keyCode': 106, 'code': 'NumpadMultiply', 'key': '*', 'location': 3 },
      'add': { 'keyCode': 107, 'code': 'NumpadAdd', 'key': '+', 'location': 3 },
      'subtract': { 'keyCode': 109, 'code': 'NumpadSubtract', 'key': '-', 'location': 3 },
      'divide': { 'keyCode': 111, 'code': 'NumpadDivide', 'key': '/', 'location': 3 },
      'numpad_enter': { 'keyCode': 13, 'code': 'NumpadEnter', 'key': 'Enter', 'text': "\r", 'location': 3 },
      'power': { 'key': 'Power', 'code': 'Power' },
      'eject': { 'key': 'Eject', 'code': 'Eject' },
      'abort': { 'keyCode': 3, 'code': 'Abort', 'key': 'Cancel' },
      'help': { 'keyCode': 6, 'code': 'Help', 'key': 'Help' },
      'backspace': { 'keyCode': 8, 'code': 'Backspace', 'key': 'Backspace' },
      'tab': { 'keyCode': 9, 'code': 'Tab', 'key': 'Tab' },
      'enter': { 'keyCode': 13, 'code': 'Enter', 'key': 'Enter', 'text': "\r" },
      "\r": { 'keyCode': 13, 'code': 'Enter', 'key': 'Enter', 'text': "\r" },
      "\n": { 'keyCode': 13, 'code': 'Enter', 'key': 'Enter', 'text': "\r" },
      'shift_left': { 'keyCode': 16, 'code': 'ShiftLeft', 'key': 'Shift', 'location': 1 },
      'shift_right': { 'keyCode': 16, 'code': 'ShiftRight', 'key': 'Shift', 'location': 2 },
      'control_left': { 'keyCode': 17, 'code': 'ControlLeft', 'key': 'Control', 'location': 1 },
      'control_right': { 'keyCode': 17, 'code': 'ControlRight', 'key': 'Control', 'location': 2 },
      'alt_left': { 'keyCode': 18, 'code': 'AltLeft', 'key': 'Alt', 'location': 1 },
      'alt_right': { 'keyCode': 18, 'code': 'AltRight', 'key': 'Alt', 'location': 2 },
      'pause': { 'keyCode': 19, 'code': 'Pause', 'key': 'Pause' },
      'caps_lock': { 'keyCode': 20, 'code': 'CapsLock', 'key': 'CapsLock' },
      'escape': { 'keyCode': 27, 'code': 'Escape', 'key': 'Escape' },
      'convert': { 'keyCode': 28, 'code': 'Convert', 'key': 'Convert' },
      'non_convert': { 'keyCode': 29, 'code': 'NonConvert', 'key': 'NonConvert' },
      'space': { 'keyCode': 32, 'code': 'Space', 'key': ' ' },
      'page_up': { 'keyCode': 33, 'code': 'PageUp', 'key': 'PageUp' },
      'page_down': { 'keyCode': 34, 'code': 'PageDown', 'key': 'PageDown' },
      'end': { 'keyCode': 35, 'code': 'End', 'key': 'End' },
      'home': { 'keyCode': 36, 'code': 'Home', 'key': 'Home' },
      'left': { 'keyCode': 37, 'code': 'ArrowLeft', 'key': 'ArrowLeft' },
      'up': { 'keyCode': 38, 'code': 'ArrowUp', 'key': 'ArrowUp' },
      'right': { 'keyCode': 39, 'code': 'ArrowRight', 'key': 'ArrowRight' },
      'down': { 'keyCode': 40, 'code': 'ArrowDown', 'key': 'ArrowDown' },
      'select': { 'keyCode': 41, 'code': 'Select', 'key': 'Select' },
      'open': { 'keyCode': 43, 'code': 'Open', 'key': 'Execute' },
      'print_screen': { 'keyCode': 44, 'code': 'PrintScreen', 'key': 'PrintScreen' },
      'insert': { 'keyCode': 45, 'code': 'Insert', 'key': 'Insert' },
      'delete': { 'keyCode': 46, 'code': 'Delete', 'key': 'Delete' },
      'decimal': { 'keyCode': 46, 'shiftKeyCode': 110, 'code': 'NumpadDecimal', 'key': "\u0000", 'shiftKey': '.', 'location': 3 },
      'digit0': { 'keyCode': 48, 'code': 'Digit0', 'shiftKey': ')', 'key': '0' },
      'digit1': { 'keyCode': 49, 'code': 'Digit1', 'shiftKey': '!', 'key': '1' },
      'digit2': { 'keyCode': 50, 'code': 'Digit2', 'shiftKey': '@', 'key': '2' },
      'digit3': { 'keyCode': 51, 'code': 'Digit3', 'shiftKey': '#', 'key': '3' },
      'digit4': { 'keyCode': 52, 'code': 'Digit4', 'shiftKey': '$', 'key': '4' },
      'digit5': { 'keyCode': 53, 'code': 'Digit5', 'shiftKey': '%', 'key': '5' },
      'digit6': { 'keyCode': 54, 'code': 'Digit6', 'shiftKey': '^', 'key': '6' },
      'digit7': { 'keyCode': 55, 'code': 'Digit7', 'shiftKey': '&', 'key': '7' },
      'digit8': { 'keyCode': 56, 'code': 'Digit8', 'shiftKey': '*', 'key': '8' },
      'digit9': { 'keyCode': 57, 'code': 'Digit9', 'shiftKey': "\(", 'key': '9' },
      'meta_left': { 'keyCode': 91, 'code': 'MetaLeft', 'key': 'Meta' },
      'meta_right': { 'keyCode': 92, 'code': 'MetaRight', 'key': 'Meta' },
      'context_menu': { 'keyCode': 93, 'code': 'ContextMenu', 'key': 'ContextMenu' },
      'F1': { 'keyCode': 112, 'code': 'F1', 'key': 'F1' },
      'f2': { 'keyCode': 113, 'code': 'F2', 'key': 'F2' },
      'f3': { 'keyCode': 114, 'code': 'F3', 'key': 'F3' },
      'f4': { 'keyCode': 115, 'code': 'F4', 'key': 'F4' },
      'f5': { 'keyCode': 116, 'code': 'F5', 'key': 'F5' },
      'f6': { 'keyCode': 117, 'code': 'F6', 'key': 'F6' },
      'f7': { 'keyCode': 118, 'code': 'F7', 'key': 'F7' },
      'f8': { 'keyCode': 119, 'code': 'F8', 'key': 'F8' },
      'f9': { 'keyCode': 120, 'code': 'F9', 'key': 'F9' },
      'f10': { 'keyCode': 121, 'code': 'F10', 'key': 'F10' },
      'f11': { 'keyCode': 122, 'code': 'F11', 'key': 'F11' },
      'f12': { 'keyCode': 123, 'code': 'F12', 'key': 'F12' },
      'f13': { 'keyCode': 124, 'code': 'F13', 'key': 'F13' },
      'f14': { 'keyCode': 125, 'code': 'F14', 'key': 'F14' },
      'f15': { 'keyCode': 126, 'code': 'F15', 'key': 'F15' },
      'f16': { 'keyCode': 127, 'code': 'F16', 'key': 'F16' },
      'f17': { 'keyCode': 128, 'code': 'F17', 'key': 'F17' },
      'f18': { 'keyCode': 129, 'code': 'F18', 'key': 'F18' },
      'f19': { 'keyCode': 130, 'code': 'F19', 'key': 'F19' },
      'f20': { 'keyCode': 131, 'code': 'F20', 'key': 'F20' },
      'f21': { 'keyCode': 132, 'code': 'F21', 'key': 'F21' },
      'f22': { 'keyCode': 133, 'code': 'F22', 'key': 'F22' },
      'f23': { 'keyCode': 134, 'code': 'F23', 'key': 'F23' },
      'f24': { 'keyCode': 135, 'code': 'F24', 'key': 'F24' },
      'num_lock': { 'keyCode': 144, 'code': 'NumLock', 'key': 'NumLock' },
      'scroll_lock': { 'keyCode': 145, 'code': 'ScrollLock', 'key': 'ScrollLock' },
      'audio_volume_mute': { 'keyCode': 173, 'code': 'AudioVolumeMute', 'key': 'AudioVolumeMute' },
      'audio_volume_down': { 'keyCode': 174, 'code': 'AudioVolumeDown', 'key': 'AudioVolumeDown' },
      'audio_volume_up': { 'keyCode': 175, 'code': 'AudioVolumeUp', 'key': 'AudioVolumeUp' },
      'media_track_next': { 'keyCode': 176, 'code': 'MediaTrackNext', 'key': 'MediaTrackNext' },
      'media_track_previous': { 'keyCode': 177, 'code': 'MediaTrackPrevious', 'key': 'MediaTrackPrevious' },
      'media_stop': { 'keyCode': 178, 'code': 'MediaStop', 'key': 'MediaStop' },
      'media_play_pause': { 'keyCode': 179, 'code': 'MediaPlayPause', 'key': 'MediaPlayPause' },
      'semicolon': { 'keyCode': 186, 'code': 'Semicolon', 'shiftKey': ':', 'key': ';' },
      'equals': { 'keyCode': 187, 'code': 'Equal', 'shiftKey': '+', 'key': '=' },
      'equal': { 'keyCode': 187, 'code': 'NumpadEqual', 'key': '=', 'location': 3 },
      'comma': { 'keyCode': 188, 'code': 'Comma', 'shiftKey': "\<", 'key': ',' },
      'minus': { 'keyCode': 189, 'code': 'Minus', 'shiftKey': '_', 'key': '-' },
      'period': { 'keyCode': 190, 'code': 'Period', 'shiftKey': '>', 'key': '.' },
      'slash': { 'keyCode': 191, 'code': 'Slash', 'shiftKey': '?', 'key': '/' },
      'backquote': { 'keyCode': 192, 'code': 'Backquote', 'shiftKey': '~', 'key': '`' },
      'bracket_left': { 'keyCode': 219, 'code': 'BracketLeft', 'shiftKey': '{', 'key': '[' },
      'backslash': { 'keyCode': 220, 'code': 'Backslash', 'shiftKey': '|', 'key': '\\' },
      'bracket_right': { 'keyCode': 221, 'code': 'BracketRight', 'shiftKey': '}', 'key': ']' },
      'quote': { 'keyCode': 222, 'code': 'Quote', 'shiftKey': '"', 'key': "'" },
      'alt_graph': { 'keyCode': 225, 'code': 'AltGraph', 'key': 'AltGraph' },
      'props': { 'keyCode': 247, 'code': 'Props', 'key': 'CrSel' },
      'cancel': { 'keyCode': 3, 'key': 'Cancel', 'code': 'Abort' },
      'clear': { 'keyCode': 12, 'key': 'Clear', 'code': 'Numpad5', 'location': 3 },
      'shift': { 'keyCode': 16, 'key': 'Shift', 'code': 'ShiftLeft' },
      'control': { 'keyCode': 17, 'key': 'Control', 'code': 'ControlLeft' },
      'ctrl': { 'keyCode': 17, 'key': 'Control', 'code': 'ControlLeft' },
      'alt': { 'keyCode': 18, 'key': 'Alt', 'code': 'AltLeft' },
      'accept': { 'keyCode': 30, 'key': 'Accept' },
      'mode_change': { 'keyCode': 31, 'key': 'ModeChange' },
      ' ': { 'keyCode': 32, 'key': ' ', 'code': 'Space' },
      'print': { 'keyCode': 42, 'key': 'Print' },
      'execute': { 'keyCode': 43, 'key': 'Execute', 'code': 'Open' },
      "\u0000": { 'keyCode': 46, 'key': "\u0000", 'code': 'NumpadDecimal', 'location': 3 },
      'a': { 'keyCode': 65, 'code': 'KeyA', 'shiftKey': 'A', 'key': 'a' },
      'b': { 'keyCode': 66, 'code': 'KeyB', 'shiftKey': 'B', 'key': 'b' },
      'c': { 'keyCode': 67, 'code': 'KeyC', 'shiftKey': 'C', 'key': 'c' },
      'd': { 'keyCode': 68, 'code': 'KeyD', 'shiftKey': 'D', 'key': 'd' },
      'e': { 'keyCode': 69, 'code': 'KeyE', 'shiftKey': 'E', 'key': 'e' },
      'f': { 'keyCode': 70, 'code': 'KeyF', 'shiftKey': 'F', 'key': 'f' },
      'g': { 'keyCode': 71, 'code': 'KeyG', 'shiftKey': 'G', 'key': 'g' },
      'h': { 'keyCode': 72, 'code': 'KeyH', 'shiftKey': 'H', 'key': 'h' },
      'i': { 'keyCode': 73, 'code': 'KeyI', 'shiftKey': 'I', 'key': 'i' },
      'j': { 'keyCode': 74, 'code': 'KeyJ', 'shiftKey': 'J', 'key': 'j' },
      'k': { 'keyCode': 75, 'code': 'KeyK', 'shiftKey': 'K', 'key': 'k' },
      'l': { 'keyCode': 76, 'code': 'KeyL', 'shiftKey': 'L', 'key': 'l' },
      'm': { 'keyCode': 77, 'code': 'KeyM', 'shiftKey': 'M', 'key': 'm' },
      'n': { 'keyCode': 78, 'code': 'KeyN', 'shiftKey': 'N', 'key': 'n' },
      'o': { 'keyCode': 79, 'code': 'KeyO', 'shiftKey': 'O', 'key': 'o' },
      'p': { 'keyCode': 80, 'code': 'KeyP', 'shiftKey': 'P', 'key': 'p' },
      'q': { 'keyCode': 81, 'code': 'KeyQ', 'shiftKey': 'Q', 'key': 'q' },
      'r': { 'keyCode': 82, 'code': 'KeyR', 'shiftKey': 'R', 'key': 'r' },
      's': { 'keyCode': 83, 'code': 'KeyS', 'shiftKey': 'S', 'key': 's' },
      't': { 'keyCode': 84, 'code': 'KeyT', 'shiftKey': 'T', 'key': 't' },
      'u': { 'keyCode': 85, 'code': 'KeyU', 'shiftKey': 'U', 'key': 'u' },
      'v': { 'keyCode': 86, 'code': 'KeyV', 'shiftKey': 'V', 'key': 'v' },
      'w': { 'keyCode': 87, 'code': 'KeyW', 'shiftKey': 'W', 'key': 'w' },
      'x': { 'keyCode': 88, 'code': 'KeyX', 'shiftKey': 'X', 'key': 'x' },
      'y': { 'keyCode': 89, 'code': 'KeyY', 'shiftKey': 'Y', 'key': 'y' },
      'z': { 'keyCode': 90, 'code': 'KeyZ', 'shiftKey': 'Z', 'key': 'z' },
      'meta': { 'keyCode': 91, 'key': 'Meta', 'code': 'MetaLeft' },
      'command': { 'keyCode': 91, 'key': 'Meta', 'code': 'MetaLeft' },
      '*': { 'keyCode': 106, 'key': '*', 'code': 'NumpadMultiply', 'location': 3 },
      '+': { 'keyCode': 107, 'key': '+', 'code': 'NumpadAdd', 'location': 3 },
      '-': { 'keyCode': 109, 'key': '-', 'code': 'NumpadSubtract', 'location': 3 },
      '/': { 'keyCode': 111, 'key': '/', 'code': 'NumpadDivide', 'location': 3 },
      ';': { 'keyCode': 186, 'key': ';', 'code': 'Semicolon' },
      '=': { 'keyCode': 187, 'key': '=', 'code': 'Equal' },
      ',': { 'keyCode': 188, 'key': ',', 'code': 'Comma' },
      '.': { 'keyCode': 190, 'key': '.', 'code': 'Period' },
      '`': { 'keyCode': 192, 'key': '`', 'code': 'Backquote' },
      '[': { 'keyCode': 219, 'key': '[', 'code': 'BracketLeft' },
      '\\': { 'keyCode': 220, 'key': '\\', 'code': 'Backslash' },
      ']': { 'keyCode': 221, 'key': ']', 'code': 'BracketRight' },
      '\'': { 'keyCode': 222, 'key': '\'', 'code': 'Quote' },
      'attn': { 'keyCode': 246, 'key': 'Attn' },
      'cr_sel': { 'keyCode': 247, 'key': 'CrSel', 'code': 'Props' },
      'ex_sel': { 'keyCode': 248, 'key': 'ExSel' },
      'erase_eof': { 'keyCode': 249, 'key': 'EraseEof' },
      'play': { 'keyCode': 250, 'key': 'Play' },
      'zoom_out': { 'keyCode': 251, 'key': 'ZoomOut' },
      ')': { 'keyCode': 48, 'key': ')', 'code': 'Digit0' },
      '!': { 'keyCode': 49, 'key': '!', 'code': 'Digit1' },
      '@': { 'keyCode': 50, 'key': '@', 'code': 'Digit2' },
      '#': { 'keyCode': 51, 'key': '#', 'code': 'Digit3' },
      '$': { 'keyCode': 52, 'key': '$', 'code': 'Digit4' },
      '%': { 'keyCode': 53, 'key': '%', 'code': 'Digit5' },
      '^': { 'keyCode': 54, 'key': '^', 'code': 'Digit6' },
      '&': { 'keyCode': 55, 'key': '&', 'code': 'Digit7' },
      '(': { 'keyCode': 57, 'key': "\(", 'code': 'Digit9' },
      'A': { 'keyCode': 65, 'key': 'A', 'code': 'KeyA' },
      'B': { 'keyCode': 66, 'key': 'B', 'code': 'KeyB' },
      'C': { 'keyCode': 67, 'key': 'C', 'code': 'KeyC' },
      'D': { 'keyCode': 68, 'key': 'D', 'code': 'KeyD' },
      'E': { 'keyCode': 69, 'key': 'E', 'code': 'KeyE' },
      'F': { 'keyCode': 70, 'key': 'F', 'code': 'KeyF' },
      'G': { 'keyCode': 71, 'key': 'G', 'code': 'KeyG' },
      'H': { 'keyCode': 72, 'key': 'H', 'code': 'KeyH' },
      'I': { 'keyCode': 73, 'key': 'I', 'code': 'KeyI' },
      'J': { 'keyCode': 74, 'key': 'J', 'code': 'KeyJ' },
      'K': { 'keyCode': 75, 'key': 'K', 'code': 'KeyK' },
      'L': { 'keyCode': 76, 'key': 'L', 'code': 'KeyL' },
      'M': { 'keyCode': 77, 'key': 'M', 'code': 'KeyM' },
      'N': { 'keyCode': 78, 'key': 'N', 'code': 'KeyN' },
      'O': { 'keyCode': 79, 'key': 'O', 'code': 'KeyO' },
      'P': { 'keyCode': 80, 'key': 'P', 'code': 'KeyP' },
      'Q': { 'keyCode': 81, 'key': 'Q', 'code': 'KeyQ' },
      'R': { 'keyCode': 82, 'key': 'R', 'code': 'KeyR' },
      'S': { 'keyCode': 83, 'key': 'S', 'code': 'KeyS' },
      'T': { 'keyCode': 84, 'key': 'T', 'code': 'KeyT' },
      'U': { 'keyCode': 85, 'key': 'U', 'code': 'KeyU' },
      'V': { 'keyCode': 86, 'key': 'V', 'code': 'KeyV' },
      'W': { 'keyCode': 87, 'key': 'W', 'code': 'KeyW' },
      'X': { 'keyCode': 88, 'key': 'X', 'code': 'KeyX' },
      'Y': { 'keyCode': 89, 'key': 'Y', 'code': 'KeyY' },
      'Z': { 'keyCode': 90, 'key': 'Z', 'code': 'KeyZ' },
      ':': { 'keyCode': 186, 'key': ':', 'code': 'Semicolon' },
      '<': { 'keyCode': 188, 'key': "\<", 'code': 'Comma' },
      '_': { 'keyCode': 189, 'key': '_', 'code': 'Minus' },
      '>': { 'keyCode': 190, 'key': '>', 'code': 'Period' },
      '?': { 'keyCode': 191, 'key': '?', 'code': 'Slash' },
      '~': { 'keyCode': 192, 'key': '~', 'code': 'Backquote' },
      '{': { 'keyCode': 219, 'key': '{', 'code': 'BracketLeft' },
      '|': { 'keyCode': 220, 'key': '|', 'code': 'Backslash' },
      '}': { 'keyCode': 221, 'key': '}', 'code': 'BracketRight' },
      '"': { 'keyCode': 222, 'key': '"', 'code': 'Quote' }
    }.freeze
    # rubocop:enable Metrics/LineLength
  end
end
