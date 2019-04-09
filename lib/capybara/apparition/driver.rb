# frozen_string_literal: true

require 'uri'
require 'forwardable'
require 'capybara/apparition/driver/chrome_client'
require 'capybara/apparition/driver/launcher'
require 'capybara/apparition/configuration'

module Capybara::Apparition
  class Driver < Capybara::Driver::Base
    DEFAULT_TIMEOUT = 30

    extend Forwardable

    attr_reader :app, :options

    delegate %i[restart current_url status_code body
                title frame_title frame_url switch_to_frame
                window_handles close_window switch_to_window
                paper_size= zoom_factor=
                scroll_to
                network_traffic clear_network_traffic
                headers headers= add_headers
                cookies all_cookies remove_cookie clear_cookies cookies_enabled=
                clear_memory_cache
                go_back go_forward refresh
                console_messages] => :browser

    def initialize(app, options = {})
      @app       = app
      @options   = options
      generate_browser_options
      @browser   = nil
      @inspector = nil
      @client    = nil
      @launcher  = nil
      @started   = false
    end

    def needs_server?
      true
    end

    # def chrome_url
    #   'ws://localhost:9223'
    # end

    def browser
      @browser ||= begin
        Browser.new(client, browser_logger) do |browser|
          browser.js_errors = options.fetch(:js_errors, true)
          browser.ignore_https_errors = options.fetch(:ignore_https_errors, false)
          browser.extensions = options.fetch(:extensions, [])
          browser.debug      = options.fetch(:debug, false)
          browser.url_blacklist = options[:url_blacklist] || []
          browser.url_whitelist = options[:url_whitelist] || []
        end
      end
    end

    def inspector
      @inspector ||= options[:inspector] && Inspector.new(options[:inspector])
    end

    def client
      @client ||= begin
        @launcher ||= Browser::Launcher.start(
          headless: options.fetch(:headless, true),
          browser_options: browser_options
        )
        ws_url = @launcher.ws_url
        ::Capybara::Apparition::ChromeClient.client(ws_url.to_s)
      end
    end

    def quit
      @client&.stop
      @launcher&.stop
    end

    # logger should be an object that responds to puts, or nil
    def logger
      options[:logger] || (options[:debug] && STDERR)
    end

    # logger should be an object that behaves like IO or nil
    def browser_logger
      options.fetch(:browser_logger, $stdout)
    end

    def visit(url)
      @started = true
      browser.visit(url)
    end

    alias html body

    def source
      browser.source.to_s
    end

    def find(method, selector)
      browser.find(method, selector).map { |page_id, id| Capybara::Apparition::Node.new(self, page_id, id) }
    end

    def find_xpath(selector)
      find :xpath, selector.to_s
    end

    def find_css(selector)
      find :css, selector.to_s
    end

    def click(x, y)
      browser.click_coordinates(x, y)
    end

    def evaluate_script(script, *args)
      unwrap_script_result(browser.evaluate(script, *native_args(args)))
    end

    def evaluate_async_script(script, *args)
      unwrap_script_result(browser.evaluate_async(script, session_wait_time, *native_args(args)))
    end

    def execute_script(script, *args)
      browser.execute(script, *native_args(args))
      nil
    end

    def current_window_handle
      browser.current_window_handle
    end

    def no_such_window_error
      NoSuchWindowError
    end

    def reset!
      begin
        browser.reset
      rescue TimeoutError
        puts 'Reset timed out - retrying'
        browser.reset
      end
      browser.url_blacklist = options[:url_blacklist] || []
      browser.url_whitelist = options[:url_whitelist] || []
      @started = false
    end

    def save_screenshot(path, options = {})
      browser.render(path, options)
    end
    alias render save_screenshot

    def render_base64(format = :png, options = {})
      browser.render_base64(options.merge(format: format))
    end

    def resize(width, height)
      browser.resize(width, height, screen: options[:screen_size])
    end

    def resize_window(width, height)
      warn '[DEPRECATION] Capybara::Apparition::Driver#resize_window ' \
        'is deprecated. Please use Capybara::Window#resize_to instead.'
      resize(width, height)
    end

    def resize_window_to(handle, width, height)
      _within_window(handle) do
        resize(width, height)
      end
    end

    def maximize_window(handle)
      _within_window(handle) do
        browser.maximize
      end
    end

    def fullscreen_window(handle)
      _within_window(handle) do
        browser.fullscreen
      end
    end

    def window_size(handle)
      _within_window(handle) do
        evaluate_script('[window.innerWidth, window.innerHeight]')
      end
    end

    def set_proxy(host, port, type = nil, user_ = nil, password_ = nil, user: nil, password: nil, bypass: [])
      if user_ || password_
        warn '#set_proxy: Passing `user` and `password` as positional arguments is deprecated. ' \
             'Please pass as keyword arguments.'
        user ||= user_
        password ||= password_
      end

      # TODO: Look at implementing via the CDP Fetch domain when available
      @options[:browser_options] ||= {}
      @options[:browser_options]['proxy-server'] = "#{type + '=' if type}#{host}:#{port}"
      bypass = Array(bypass).join(';')
      @options[:browser_options]['proxy-bypass-list'] = bypass unless bypass.empty?
      browser.set_proxy_auth(user, password) if user || password
    end

    def add_header(name, value, options = {})
      browser.add_header({ name => value }, { permanent: true }.merge(options))
    end
    alias_method :header, :add_header

    def response_headers
      browser.response_headers.each_with_object({}) do |(key, value), hsh|
        hsh[key.split('-').map(&:capitalize).join('-')] = value
      end
    end

    def set_cookie(name, value = nil, options = {})
      name, value, options = parse_raw_cookie(name) if value.nil?

      options[:name]  ||= name
      options[:value] ||= value
      options[:domain] ||= begin
        if @started
          URI.parse(browser.current_url).host
        else
          URI.parse(default_cookie_host).host || '127.0.0.1'
        end
      end

      browser.set_cookie(options)
    end

    def proxy_authorize(user = nil, password = nil)
      browser.set_proxy_aauth(user, password)
    end

    def basic_authorize(user = nil, password = nil)
      browser.set_http_auth(user, password)
    end
    alias_method :authenticate, :basic_authorize

    def debug
      if @options[:inspector]
        # Fall back to default scheme
        scheme = begin
                   URI.parse(browser.current_url).scheme
                 rescue StandardError
                   nil
                 end
        scheme = 'http' if scheme != 'https'
        inspector.open(scheme)
        pause
      else
        raise Error, 'To use the remote debugging, you have to launch the driver ' \
                     'with `:inspector => true` configuration option'
      end
    end

    def pause
      # STDIN is not necessarily connected to a keyboard. It might even be closed.
      # So we need a method other than keypress to continue.

      # In jRuby - STDIN returns immediately from select
      # see https://github.com/jruby/jruby/issues/1783
      # TODO: This limitation is no longer true can we simplify?
      read, write = IO.pipe
      Thread.new do
        IO.copy_stream(STDIN, write)
        write.close
      end

      STDERR.puts "Apparition execution paused. Press enter (or run 'kill -CONT #{Process.pid}') to continue." # rubocop:disable Style/StderrPuts

      signal = false
      old_trap = trap('SIGCONT') do
        signal = true
        STDERR.puts "\nSignal SIGCONT received" # rubocop:disable Style/StderrPuts
      end
      # wait for data on STDIN or signal SIGCONT received
      keyboard = IO.select([read], nil, nil, 1) until keyboard || signal

      unless signal
        begin
          input = read.read_nonblock(80) # clear out the read buffer
          puts unless input&.end_with?("\n")
        rescue EOFError, IO::WaitReadable # rubocop:disable Lint/HandleExceptions
          # Ignore problems reading from STDIN.
        end
      end
    ensure
      trap('SIGCONT', old_trap) # Restore the previous signal handler, if there was one.
      STDERR.puts 'Continuing' # rubocop:disable Style/StderrPuts
    end

    def wait?
      true
    end

    def invalid_element_errors
      [Capybara::Apparition::ObsoleteNode, Capybara::Apparition::MouseEventFailed, Capybara::Apparition::WrongWorld]
    end

    def accept_modal(type, options = {})
      case type
      when :alert
        browser.accept_alert
      when :confirm
        browser.accept_confirm
      when :prompt
        browser.accept_prompt options[:with]
      end

      yield if block_given?

      find_modal(options)
    end

    def dismiss_modal(type, options = {})
      case type
      when :confirm
        browser.dismiss_confirm
      when :prompt
        browser.dismiss_prompt
      end

      yield if block_given?
      find_modal(options)
    end

    def timeout
      client.timeout
    end

    def timeout=(sec)
      client.timeout = sec
    end

    def error_messages
      console_messages('error')
    end

    def within_window(selector, &block)
      warn 'Driver#within_window is deprecated, please switch to using Session#within_window instead.'
      _within_window(selector, &block)
      orig_window = current_window_handle
      switch_to_window(selector)
      begin
        yield
      ensure
        switch_to_window(orig_window)
      end
    end

    def version
      chrome_version = browser.command('Browser.getVersion')
      format(VERSION_STRING,
             capybara: Capybara::VERSION,
             apparition: Capybara::Apparition::VERSION,
             chrome: chrome_version['product'])
    end

    def open_new_window
      # needed because Capybara does arity detection on this method
      browser.open_new_window
    end

  private

    def _within_window(selector)
      orig_window = current_window_handle
      switch_to_window(selector)
      begin
        yield
      ensure
        switch_to_window(orig_window)
      end
    end

    def browser_options
      @options[:browser_options]
    end

    def generate_browser_options
      # TODO: configure SSL options
      # PhantomJS defaults to only using SSLv3, which since POODLE (Oct 2014)
      # many sites have dropped from their supported protocols (eg PayPal,
      # Braintree).
      # list += ["--ignore-ssl-errors=yes"] unless list.grep(/ignore-ssl-errors/).any?
      # list += ["--ssl-protocol=TLSv1"] unless list.grep(/ssl-protocol/).any?
      # list += ["--remote-debugger-port=#{inspector.port}", "--remote-debugger-autorun=yes"] if inspector
      # Note: Need to verify what Chrome command line options are valid for this
      browser_options = {}
      browser_options['remote-debugging-port'] = @options[:port] || 0
      browser_options['remote-debugging-address'] = @options[:host] if @options[:host]
      browser_options['window-size'] = @options[:window_size].join(',') if @options[:window_size]
      if @options[:browser]
        warn ':browser is deprecated, please pass as :browser_options instead.'
        browser_options.merge! process_browser_options(@options[:browser])
      end
      browser_options.merge! process_browser_options(@options[:browser_options]) if @options[:browser_options]
      if @options[:skip_image_loading]
        browser_options['blink-settings'] = [browser_options['blink-settings'], 'imagesEnabled=false'].compact.join(',')
      end

      @options[:browser_options] = browser_options
      process_cw_options(@options[:cw_options])
    end

    def process_cw_options(cw_options)
      return if cw_options.nil?

      (options[:url_blacklist] ||= []).concat cw_options[:url_blacklist]
      options[:js_errors] ||= cw_options[:js_errors]
    end

    def process_browser_options(options)
      case options
      when Array
        options.compact.each_with_object({}) do |option, hsh|
          if option.is_a? Hash
            hsh.merge! process_browser_options(option)
          else
            hsh[option.to_s.tr('_', '-')] = nil
          end
        end
      when Hash
        options.each_with_object({}) { |(option, val), hsh| hsh[option.to_s.tr('_', '-')] = val }
      else
        raise ArgumentError, 'browser_options must be an Array or a Hash'
      end
    end

    def parse_raw_cookie(raw)
      parts = raw.split(/;\s*/)
      name, value = parts[0].split('=', 2)
      options = parts[1..-1].each_with_object({}) do |part, opts|
        name, value = part.split('=', 2)
        opts[name.to_sym] = value
      end
      [name, value, options]
    end

    def screen_size
      options[:screen_size] || [1366, 768]
    end

    def find_modal(options)
      timeout_sec   = options.fetch(:wait) { session_wait_time }
      expect_text   = options[:text]
      expect_regexp = expect_text.is_a?(Regexp) ? expect_text : Regexp.escape(expect_text.to_s)
      timer = Capybara::Helpers.timer(expire_in: timeout_sec)
      begin
        modal_text = browser.modal_message
        found_text ||= modal_text
        raise Capybara::ModalNotFound if modal_text.nil? || (expect_text && !modal_text.match(expect_regexp))
      rescue Capybara::ModalNotFound => e
        if timer.expired?
          raise e, 'Timed out waiting for modal dialog. Unable to find modal dialog.' unless found_text

          raise e, 'Unable to find modal dialog' \
                   "#{" with #{expect_text}" if expect_text}" \
                   "#{", did find modal with #{found_text}" if found_text}"
        end
        sleep(0.05)
        retry
      end
      modal_text
    end

    def session_wait_time
      if respond_to?(:session_options)
        session_options.default_max_wait_time
      else
        begin begin
                Capybara.default_max_wait_time
              rescue StandardError
                Capybara.default_wait_time
              end end
      end
    end

    def default_cookie_host
      if respond_to?(:session_options)
        session_options.app_host
      else
        Capybara.app_host
      end || ''
    end

    def native_args(args)
      args.map { |arg| arg.is_a?(Capybara::Apparition::Node) ? arg.native : arg }
    end

    def unwrap_script_result(arg, object_cache = {})
      return object_cache[arg] if object_cache.key? arg

      case arg
      when Array
        object_cache[arg] = []
        object_cache[arg].replace(arg.map { |e| unwrap_script_result(e, object_cache) })
        object_cache[arg]
      when Hash
        if (arg['subtype'] == 'node') && arg['objectId']
          Capybara::Apparition::Node.new(self, browser.current_page, arg['objectId'])
        else
          object_cache[arg] = {}
          arg.each { |k, v| object_cache[arg][k] = unwrap_script_result(v, object_cache) }
          object_cache[arg]
        end
      else
        arg
      end
    end

    VERSION_STRING = <<~VERSION
      Versions in use:
      Capybara: %<capybara>s
      Apparition: %<apparition>s
      Chrome: %<chrome>s
    VERSION
  end
end
