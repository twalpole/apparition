# frozen_string_literal: true

module Capybara::Apparition::NetworkTraffic
  class Error
    attr_reader :url, :code, :description

    def initialize(url:, code:, description:)
      @url = url
      @code = code
      @description = description
    end
  end
end
