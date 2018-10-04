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

    def httponly?
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
  end
end
