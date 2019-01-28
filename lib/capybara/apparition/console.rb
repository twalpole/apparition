# frozen_string_literal: true

module Capybara::Apparition
  class Console
    def initialize(logger = nil)
      @logger = logger
      @messages = []
    end

    def log(type, message)
      @messages << OpenStruct.new(type: type, message: message)
      @logger&.puts message
    end

    def clear
      @messages.clear
    end

    def messages(type = nil)
      return @message if type.nil?

      @messages.select { |msg| msg.type.to_sym == type }
    end
  end
end
