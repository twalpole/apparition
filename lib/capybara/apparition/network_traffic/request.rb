# frozen_string_literal: true

module Capybara::Apparition::NetworkTraffic
  class Request
    attr_reader :response_parts, :error, :response
    attr_writer :blocked_params

    def initialize(data, response_parts = [], error = nil)
      @data           = data
      @response_parts = response_parts
      @response = nil
      @error = error
      @blocked_params = nil
    end

    def response=(response)
      @response_parts.push response
    end

    def request_id
      @data['requestId']
    end

    def url
      @data.dig('request', 'url')
    end

    def method
      @data.dig('request', 'method')
    end

    def headers
      @data.dig('requst', 'headers')
    end

    def time
      @data['timestamp'] && Time.parse(@data['timestamp'])
    end

    def blocked?
      !@blocked_params.nil?
    end
  end
end
