# frozen_string_literal: true

module Capybara
  module Apparition
    class Error < StandardError; end
    class NoSuchWindowError < Error; end

    class ClientError < Error
      attr_reader :response

      def initialize(response)
        @response = response
      end
    end

    class CDPError < Error
      attr_reader :message, :code

      def initialize(error)
        @message = error['message']
        @code = error['code']
      end
    end

    class JSErrorItem
      attr_reader :message, :stack

      def initialize(message, stack)
        @message = message
        @stack   = stack
      end

      def to_s
        [message, stack].join("\n")
      end
    end

    class BrowserError < ClientError
      def name
        response['name']
      end

      def error_parameters
        (response['args'] || []).join("\n")
      end

      def message
        'There was an error inside Apparition. ' \
          'If this is the error returned, and not the cause of a more detailed error response, ' \
          'this is probably a bug, so please report it. ' \
          "\n\n#{name}: #{error_parameters}"
      end
    end

    class JavascriptError < ClientError
      # def javascript_errors
      #   response['args'].first.map { |data| JSErrorItem.new(data['message'], data['stack']) }
      # end
      def javascript_errors
        [message: response]
      end

      def message
        'One or more errors were raised in the Javascript code on the page. ' \
          "If you don't care about these errors, you can ignore them by " \
          'setting js_errors: false in your Apparition configuration (see ' \
          'documentation for details).' \
          "\n\n#{javascript_errors.map { |err| err[:message] }.join("\n")}"
      end
    end

    class StatusFailError < ClientError
      def url
        response['args'].first
      end

      def details
        response['args'][1]
      end

      def message
        msg = "Request to '#{url}' failed to reach server, check DNS and/or server status"
        msg += " - #{details}" if details
        msg
      end
    end

    class FrameNotFound < ClientError
      def name
        response['args'].first
      end

      def message
        "The frame '#{name}' was not found."
      end
    end

    class InvalidSelector < ClientError
      def method
        response['args'][0]
      end

      def selector
        response['args'][1]
      end

      def message
        'The browser raised a syntax error while trying to evaluate ' \
          "#{method} selector #{selector.inspect}"
      end
    end

    class NodeError < ClientError
      attr_reader :node

      def initialize(node, response)
        @node = node
        super(response)
      end
    end

    class ObsoleteNode < NodeError
      def message
        'The element you are trying to interact with is either not part of the DOM, or is ' \
          'not currently visible on the page (perhaps display: none is set). ' \
          "It's possible the element has been replaced by another element and you meant to interact with " \
          "the new element. If so you need to do a new 'find' in order to get a reference to the " \
          'new element.'
      end
    end
    NodeNotAttachedError = ObsoleteNode

    class WrongWorld < ObsoleteNode
      def message
        'The element you are trying to access is not from the current page'
      end
    end

    class UnsupportedFeature < ClientError
      def name
        response['name']
      end

      def unsupported_message
        response['args'][0]
      end

      def version
        response['args'][1].values_at('major', 'minor', 'patch').join '.'
      end

      def message
        "Running version of Chrome #{version} does not support some feature: #{unsupported_message}"
      end
    end

    class MouseEventFailed < NodeError
      def name
        response['args'][0]
      end

      def selector
        response['args'][1]
      end

      def position
        [response['args'][2][:x], response['args'][2][:y]]
      end

      def message
        "Firing a #{name} at co-ordinates [#{position.join(', ')}] failed. Apparition detected " \
          "another element with CSS selector '#{selector}' at this position. " \
          'It may be overlapping the element you are trying to interact with. '
      end
    end
    ClickFailed = MouseEventFailed

    class MouseEventImpossible < MouseEventFailed
      def name
        response['args'][0]
      end

      def selector
        nil
      end

      def position
        nil
      end

      def message
        "Firing a #{name} event is not possible since the element has no visible position on the page."
      end
    end

    class KeyError < ::ArgumentError
      def initialize(key)
        super(key)
      end
    end

    class TimeoutError < Error
      def initialize(message = nil)
        @message = message
      end

      def message
        "Timed out waiting for response to #{@message}. It's possible that this happened " \
          'because something took a very long time (for example a page load was slow). ' \
          'If so, setting the Apparition :timeout option to a higher value will help ' \
          '(see the docs for details). If increasing the timeout does not help, this is ' \
          'probably a bug in Apparition - please report it to the issue tracker.'
      end
    end

    class ScriptTimeoutError < Error
      def message
        'Timed out waiting for evaluated script to resturn a value'
      end
    end

    class DeadClient < Error
      def initialize(message)
        @message = message
      end

      def message
        "Chrome client died while processing #{@message}"
      end
    end

    class InvalidResponseError < StandardError
    end
  end
end
