# frozen_string_literal: true

require 'socket'
require 'timeout'

module Capybara::Apparition
  class Browser
    class Launcher
      class Remote
        attr_reader :ws_url

        def self.start(options)
          new(options).tap(&:start)
        end

        def initialize(options)
          @remote_host = options.fetch('remote-debugging-address', '127.0.0.1')
          @remote_port = options.fetch('remote-debugging-port', '9222')
        end

        def start
          @ws_url = Addressable::URI.parse(get_ws_url(@remote_host, @remote_port))

          true
        end

        def stop
          # Remote instance cannot be stopped
        end

        def restart
          # Remote instance cannot be restarted
        end

        def host
          ws_url.host
        end

        def port
          ws_url.port
        end

      protected

        def get_ws_url(host, port)
          response = Net::HTTP.get(host, '/json/version', port)
          response = JSON.parse(response)
          response['webSocketDebuggerUrl']
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
          raise ArgumentError, "Cannot connect to remote Chrome at: 'http://#{host}:#{port}/json/version'"
        end
      end
    end
  end
end
