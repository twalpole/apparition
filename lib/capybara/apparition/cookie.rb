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

    def httpOnly?
      @attributes['httpOnly']
    end

    def httponly?
      httpOnly?
    end

    def sameSite
      @attributes['sameSite']
    end

    def samesite
      sameSite
    end

    def expires
      Time.at @attributes['expires'] unless [nil, 0, -1].include? @attributes['expires']
    end
  end
end
