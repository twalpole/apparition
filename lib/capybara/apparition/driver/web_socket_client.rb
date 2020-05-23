# frozen_string_literal: true

require 'websocket/driver'

module Capybara::Apparition
  class WebSocketClient
    attr_reader :driver, :messages, :status

    def initialize(url)
      @socket = Socket.new(url)
      @driver = ::WebSocket::Driver.client(@socket)
      @messages = []
      @status = :closed

      setup_driver
      start_driver
    end

    def send_msg(msg)
      driver.text msg
    end

    def read_msg
      parse_input until (msg = messages.shift)
      msg
    end

    def close
      @driver.close
    end

  private

    def setup_driver
      driver.on(:message) do |e|
        messages << e.data
      end

      driver.on(:error) do |e|
        raise e.message
      end

      driver.on(:close) do |_e|
        @status = :closed
      end

      driver.on(:open) do |_e|
        @status = :open
      end
    end

    def start_driver
      driver.start
      parse_input until status == :open
    end

    def parse_input
      @driver.parse(@socket.read)
    end
  end

  require 'socket'

  class Socket
    attr_reader :url

    def initialize(url)
      @url = url
      uri = URI.parse(url)
      @io = TCPSocket.new(uri.host, uri.port)
    end

    def write(data)
      @io.print data
    end

    def read
      @io.readpartial(1024)
    end
  end
end
