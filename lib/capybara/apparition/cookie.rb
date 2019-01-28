# frozen_string_literal: true

module Capybara::Apparition
  class Cookie
    def initialize(attributes)
      @attributes = attributes
    end

    def name
      @attributes['name']
    end

    def value
      @attributes['value']
    end

    def domain
      @attributes['domain']
    end

    def path
      @attributes['path']
    end

    def secure?
      @attributes['secure']
    end

    def http_only?
      @attributes['httpOnly']
    end
    alias httponly? http_only?

    def httpOnly? # rubocop:disable Naming/MethodName
      warn 'httpOnly? is deprecated, please use http_only? instead'
      http_only?
    end

    def same_site
      @attributes['sameSite']
    end

    def samesite
      same_site
    end

    def expires
      Time.at @attributes['expires'] unless [nil, 0, -1].include? @attributes['expires']
    end

    def ==(value)
      return super unless value.is_a? String
      self.value == value
    end
  end
end
