# frozen_string_literal: true

require 'chrome_remote/client'
require 'capybara/apparition/errors'
require 'capybara/apparition/web_socket_client'
module Capybara::Apparition
  class ChromeClient
    class << self
      DEFAULT_OPTIONS = {
        host: 'localhost',
        port: 9222
      }.freeze

      def client(options = {})
        options = DEFAULT_OPTIONS.merge(options)

        new(options[:ws_url] || get_ws_url(options))
      end

      def client2(ws_url)
        new(ws_url)
      end

    private

      def get_ws_url(options)
        response = Net::HTTP.get(options[:host], '/json', options[:port])
        # TODO: handle unsuccesful request
        response = JSON.parse(response)

        first_page = response.find { |e| e['type'] == 'page' }
        # TODO: handle no entry found
        first_page['webSocketDebuggerUrl']
      end
    end

    def initialize(ws_url)
      @ws = WebSocketClient.new(ws_url)
      @handlers = Hash.new { |hash, key| hash[key] = [] }

      @responses = {}

      @events = Queue.new

      @processor = Thread.new { process_messages }

      @listener = Thread.new do
        listen
      rescue EOFError
      end

      @send_mutex = Mutex.new
      @msg_mutex = Mutex.new
      @message_available = ConditionVariable.new
      @session_handlers = Hash.new { |hash, key| hash[key] = Hash.new { |h, k| h[k] = [] } }
    end

    def stop
      puts 'Implement client stop'
    end

    def on(event_name, session_id = nil, &block)
      return @handlers[event_name] << block unless session_id

      @session_handlers[session_id][event_name] << block
    end

    def send_cmd(command, params = {})
      msg_id = nil
      @send_mutex.synchronize do
        msg_id = generate_unique_id
        msg = { method: command, params: params, id: msg_id }.to_json
        puts "sending msg: #{msg}" if ENV['DEBUG']
        @ws.send_msg(msg)
      end

      response = nil
      while response.nil?
        @msg_mutex.synchronize do
          response = @responses.delete(msg_id)
          @message_available.wait(@msg_mutex, 0.1) if response.nil?
        end
      end
      if (error = response['error'])
        raise CDPError.new(error)
      end

      response['result']
    end

    def send_cmd_to_session(session_id, command, params = {})
      msg_id = nil
      @send_mutex.synchronize do
        msg_id = generate_unique_id
      end

      msg = { method: command, params: params, id: msg_id }
      send_cmd('Target.sendMessageToTarget', sessionId: session_id, message: msg.to_json)

      response = nil
      while response.nil?
        @msg_mutex.synchronize do
          response = @responses.delete(msg_id)
          @message_available.wait(@msg_mutex, 0.1) if response.nil?
        end
      end

      if (error = response['error'])
        case error['code']
        when -32000
          raise WrongWorld.new(nil, error)
        else
          raise CDPError.new(error)
        end
      end

      response['result']
    end

    def listen_until
      read_until { yield }
    end

    def listen
      read_until { false }
    end

  private

    def generate_unique_id
      @last_id ||= 0
      @last_id += 1
    end

    def read_until
      loop do
        msg = read_msg
        return msg if yield(msg)
      end
    end

    def read_msg
      msg = JSON.parse(@ws.read_msg)
      puts "got msg: #{msg}" if ENV['DEBUG']
      # Check if it's an event and invoke any handlers
      @events.push msg.dup if msg['method']

      if msg['method'] == 'Target.receivedMessageFromTarget'
        msg = JSON.parse(msg['params']['message'])
      end

      if msg['id']
        @msg_mutex.synchronize do
          @responses[msg['id']] = msg
          @message_available.broadcast
        end
      end
      msg
    end

    def process_messages
      # run handlers in own thread so as not to hang message processing

      loop do
        event = @events.pop
        next unless event

        if event['method'] == 'Target.receivedMessageFromTarget'
          session_id = event['params']['sessionId']
          event = JSON.parse(event['params']['message'])
          @session_handlers[session_id][event['method']].each do |handler|
            handler.call(event['params'])
          end
        end

        event_name = event['method']
        @handlers[event_name].each do |handler|
          handler.call(event['params'])
        end
      end
    rescue StandardError => e
      puts "Unexpectecd inner loop exception: #{e}: #{e.backtrace}"
      retry
    rescue Exception => e
      puts "Unexpected Outer Loop exception: #{e}"
      retry
    end
  end
end

require 'chrome_remote/web_socket_client'
