# frozen_string_literal: true

require 'websocket/driver'

module Capybara::Apparition
  class WebSocketClient
    class WebSocketClientError < StandardError; end;

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
      data = @socket.read
      raise WebSocketClientError.new("Received empty data message from websocket, indicating a timeout or dead connection.") if data.nil? || data.empty?
      @driver.parse(data)
    rescue EOFError, Errno::ECONNRESET => e
      raise WebSocketClientError.new("Received a low-level error when reading from websocket: #{e.inspect}")
    end
  end

  require 'socket'

  class Socket
    CONNECT_TIMEOUT = ENV.fetch("APPARITION_SOCKET_CONNECT_TIMEOUT", 5).to_i
    READ_TIMEOUT = ENV.fetch("APPARITION_SOCKET_READ_TIMEOUT", 5).to_i

    attr_reader :url

    def initialize(url)
      @url = url
      uri = URI.parse(url)
      @io = ::Socket.tcp(uri.host, uri.port, connect_timeout: CONNECT_TIMEOUT)
    end

    def write(data)
      @io.print data
    end

    def read
      retries = 0
      begin
        @io.read_nonblock(1024)
      rescue IO::WaitReadable
        retries += 1
        IO.select([@io], nil, nil, READ_TIMEOUT)
        retry if retries <= 1
        nil
      end
    end
  end
end
