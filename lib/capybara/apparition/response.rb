# frozen_string_literal: true

module Capybara::Apparition
  class ChromeClient
    class Response
      def initialize(client, *msg_ids, send_time: nil)
        @send_time = send_time
        @msg_ids = msg_ids
        @client = client
      end

      def result
        response = @msg_ids.map do |id|
          resp = @client.send(:wait_for_msg_response, id)
          handle_error(resp['error']) if resp['error']
          resp
        end.last
        puts "Processed msg: #{@msg_ids.last} in #{Time.now - @send_time} seconds" if ENV['DEBUG']

        response['result']
      end

      def discard_result
        @msg_ids.each { |id| @client.add_async_id id }
        @result_time = Time.now
        nil
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
    end
  end
end
