# frozen_string_literal: true

require 'securerandom'

module Capybara::Apparition
  class Command
    attr_reader :id
    attr_reader :name
    attr_accessor :args

    def initialize(name, params = {})
      @id = SecureRandom.uuid
      @name = name
      @params = params
    end

    def message
      JSON.dump('id' => @id, 'name' => @name, 'params' => @params)
    end
  end
end
