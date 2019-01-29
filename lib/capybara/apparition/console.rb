# frozen_string_literal: true

module Capybara::Apparition
  class Console
    def initialize(logger = nil)
      @logger = logger
      @messages = []
    end

    def log(type, message, **options)
      @messages << OpenStruct.new(type: type, message: message, **options)
      @logger&.puts "#{type}: #{message}"
    end

    def clear
      @messages.clear
    end

    def messages(type = nil)
      return @messages if type.nil?

      @messages.select { |msg| msg.type == type }
    end
  end
end
