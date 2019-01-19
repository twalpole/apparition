# frozen_string_literal: true

module Capybara::Apparition::NetworkTraffic
  class Request
    attr_reader :response_parts, :response
    attr_writer :blocked_params

    def initialize(data, response_parts = [])
      @data           = data
      @response_parts = response_parts
      @response = nil
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

    def error
      response_parts.last&.error
    end
  end
end
