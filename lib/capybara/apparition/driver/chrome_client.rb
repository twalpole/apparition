# frozen_string_literal: true

require 'capybara/apparition/errors'
require 'capybara/apparition/driver/web_socket_client'
require 'capybara/apparition/driver/response'

module Capybara::Apparition
  class ChromeClient
    class << self
      DEFAULT_OPTIONS = {
        host: 'localhost',
        port: 9222
      }.freeze

      def client(ws_url)
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

      @send_mutex = Mutex.new
      @msg_mutex = Mutex.new
      @message_available = ConditionVariable.new
      @session_handlers = Hash.new { |hash, key| hash[key] = Hash.new { |h, k| h[k] = [] } }
      @timeout = nil
      @async_ids = []

      start_threads
    end

    attr_accessor :timeout

    def stop
      @ws.close
    end

    def on(event_name, session_id = nil, &block)
      return @handlers[event_name] << block unless session_id

      @session_handlers[session_id][event_name] << block
    end

    def send_cmd(command, params)
      time = Time.now
      msg_id = send_msg(command, params)
      Response.new(self, msg_id, send_time: time)
    end

    def send_cmd_to_session(session_id, command, params)
      time = Time.now
      msg_id, msg = generate_msg(command, params)
      wrapper_msg_id = send_msg('Target.sendMessageToTarget', sessionId: session_id, message: msg)
      Response.new(self, wrapper_msg_id, msg_id, send_time: time)
    end

    def add_async_id(msg_id)
      @msg_mutex.synchronize do
        @async_ids.push(msg_id)
      end
    end

  private

    def handle_error(error)
      case error['code']
      when -32_000
        raise WrongWorld.new(nil, error)
      else
        raise CDPError.new(error)
      end
    end

    def send_msg(command, params)
      msg_id, msg = generate_msg(command, params)
      @send_mutex.synchronize do
        puts "#{Time.now.to_i}: sending msg: #{msg}" if ENV['DEBUG']
        @ws.send_msg(msg)
      end
      msg_id
    end

    def generate_msg(command, params)
      @send_mutex.synchronize do
        msg_id = generate_unique_id
        [msg_id, { method: command, params: params, id: msg_id }.to_json]
      end
    end

    def wait_for_msg_response(msg_id)
      @msg_mutex.synchronize do
        timer = Capybara::Helpers.timer(expire_in: @timeout)
        while (response = @responses.delete(msg_id)).nil?
          if @timeout && timer.expired?
            puts "Timedout waiting for response for msg: #{msg_id}"
            raise TimeoutError.new(msg_id)
          end
          @message_available.wait(@msg_mutex, 0.1)
        end
        response
      end
    end

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

    def listen_until
      read_until { yield }
    end

    def listen
      read_until { false }
    end

    def read_msg
      msg = JSON.parse(@ws.read_msg)
      puts "#{Time.now.to_i}: got msg: #{msg}" if ENV['DEBUG']
      # Check if it's an event and push on event queue
      @events.push msg.dup if msg['method']

      msg = JSON.parse(msg['params']['message']) if msg['method'] == 'Target.receivedMessageFromTarget'

      if msg['id']
        @msg_mutex.synchronize do
          puts "broadcasting response to #{msg['id']}" if ENV['DEBUG'] == 'V'
          @responses[msg['id']] = msg
          @message_available.broadcast
        end
      end
      msg
    end

    def cleanup_async_responses
      loop do
        @msg_mutex.synchronize do
          @message_available.wait(@msg_mutex, 0.1)
          (@responses.keys & @async_ids).each do |msg_id|
            puts "Cleaning up response for #{msg_id}" if ENV['DEBUG'] == 'v'
            @responses.delete(msg_id)
            @async_ids.delete(msg_id)
          end
        end
      end
    end

    def process_messages
      # run handlers in own thread so as not to hang message processing
      loop do
        event = @events.pop
        next unless event

        event_name = event['method']
        puts "Popped event #{event_name}" if ENV['DEBUG'] == 'V'

        if event_name == 'Target.receivedMessageFromTarget'
          session_id = event.dig('params', 'sessionId')
          event = JSON.parse(event.dig('params', 'message'))
          process_handlers(@session_handlers[session_id], event)
        end

        process_handlers(@handlers, event)
      end
    rescue CDPError => e
      if e.code == -32_602
        puts "Attempt to contact session that's gone away"
      else
        puts "Unexpected CDPError: #{e.message}"
      end
      retry
    rescue StandardError => e
      puts "Unexpected inner loop exception: #{e}: #{e.message}: #{e.backtrace}"
      retry
    rescue Exception => e # rubocop:disable Lint/RescueException
      puts "Unexpected Outer Loop exception: #{e}"
      retry
    end

    def process_handlers(handlers, event)
      event_name = event['method']
      handlers[event_name].each do |handler|
        puts "Calling handler for #{event_name}" if ENV['DEBUG'] == 'V'
        handler.call(event['params'])
      end
    end

    def start_threads
      @processor = Thread.new do
        process_messages
      end
      @processor.abort_on_exception = true

      @async_response_handler = Thread.new do
        cleanup_async_responses
      end
      @async_response_handler.abort_on_exception = true

      @listener = Thread.new do
        begin
          listen
        rescue EOFError # rubocop:disable Lint/HandleExceptions
        end
      end
    end
  end
end
