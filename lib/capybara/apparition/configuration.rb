# frozen_string_literal: true

module Capybara::Apparition
  class Configuration
    class << self
    private

      def instance
        @instance ||= new
      end
    end

    def self.to_hash
      instance.freeze.to_hash
    end

    def self.modify
      raise 'All configuration must take place before the driver starts' if instance.frozen?
    end

    attr_accessor :allowed_urls
    attr_writer :block_unknown_urls
    attr_accessor :blocked_urls
    attr_accessor :debug
    attr_writer :ignore_ssl_errors
    attr_accessor :proxy
    attr_accessor :stderr
    attr_accessor :timeout
    attr_writer :skip_image_loading
    attr_accessor :raise_javascript_errors

    def initialize
      @allowed_urls = []
      @blocked_urls = []
      @block_unknown_urls = false
      @debug = false
      @ignore_ssl_errors = false
      @proxy = nil
      @skip_image_loading = false
      @stderr = $stderr
      @timeout = -1
      @raise_javascript_errors = false
    end

    def allow_url(url)
      @allowed_urls << url
    end

    def block_url(url)
      @blocked_urls << url
    end

    def block_unknown_urls
      @block_unknown_urls = true
    end

    def block_unknown_urls?
      @block_unknown_urls
    end

    def allow_unknown_urls
      allow_url('*')
    end

    def ignore_ssl_errors
      @ignore_ssl_errors = true
    end

    def ignore_ssl_errors?
      @ignore_ssl_errors
    end

    def skip_image_loading
      @skip_image_loading = true
    end

    def skip_image_loading?
      @skip_image_loading
    end

    def use_proxy(proxy)
      @proxy = proxy
    end

    def to_hash
      {
        url_whitelist: allowed_urls,
        block_unknown_urls: block_unknown_urls?,
        url_blacklist: blocked_urls,
        debug: debug,
        ignore_ssl_errors: ignore_ssl_errors?,
        proxy: proxy,
        skip_image_loading: skip_image_loading?,
        stderr: stderr,
        timeout: timeout,
        js_errors: raise_javascript_errors
      }
    end
  end
end
