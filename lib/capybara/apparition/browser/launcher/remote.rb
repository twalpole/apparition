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
          version = fetch_version(host, port)
          ws_url = version['webSocketDebuggerUrl']
          ws_url.insert(ws_url.index('/devtools'), "#{host}:#{port}")
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
          raise ArgumentError, "Cannot connect to remote Chrome at: 'http://#{host}:#{port}/json/version'"
        end

        def fetch_version(host, port)
          uri = URI.parse("http://#{host}:#{port}/json/version")
          http = Net::HTTP.new(uri.host, uri.port)
          request = Net::HTTP::Get.new(uri.request_uri)
          request.add_field('Host', '')
          response = http.request(request)
          JSON.parse(response.body)
        end
      end
    end
  end
end
