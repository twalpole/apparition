# frozen_string_literal: true

require 'uri'
require 'capybara/apparition/chrome_client'
require 'capybara/apparition/launcher'

module Capybara::Apparition
  class Driver < Capybara::Driver::Base
    DEFAULT_TIMEOUT = 30

    attr_reader :app, :options

    def initialize(app, options = {})
      @app       = app
      @options   = options
      @browser   = nil
      @inspector = nil
      @client    = nil
      @started   = false
    end

    def needs_server?
      true
    end

    def chrome_url
      'ws://localhost:9223'
    end

    def browser
      @browser ||= begin
        browser = Browser.new(client, browser_logger)
        browser.js_errors  = options[:js_errors] if options.key?(:js_errors)
        browser.extensions = options.fetch(:extensions, [])
        browser.debug      = true if options[:debug]
        browser.url_blacklist = options[:url_blacklist] || []
        browser.url_whitelist = options[:url_whitelist] || []
        browser
      end
    end

    def inspector
      @inspector ||= options[:inspector] && Inspector.new(options[:inspector])
    end

    def client
      @client ||= begin
        browser_options = {}
        browser_options['remote-debugging-port'] = options[:port] || 0
        browser_options['remote-debugging-address'] = options[:host] if options[:host]
        browser_options['window-size'] = options[:window_size].join(',') if options[:window_size]
        @launcher ||= ::Capybara::Apparition::Browser::Launcher.start(browser: browser_options)
        ws_url = @launcher.ws_url
        client = ::Capybara::Apparition::ChromeClient.client(ws_url.to_s)
        sleep 3
        client
      end
    end

    def browser_options
      list = options[:browser_options] || []

      # TODO: configure SSL options
      # PhantomJS defaults to only using SSLv3, which since POODLE (Oct 2014)
      # many sites have dropped from their supported protocols (eg PayPal,
      # Braintree).
      # list += ["--ignore-ssl-errors=yes"] unless list.grep(/ignore-ssl-errors/).any?
      # list += ["--ssl-protocol=TLSv1"] unless list.grep(/ssl-protocol/).any?
      # list += ["--remote-debugger-port=#{inspector.port}", "--remote-debugger-autorun=yes"] if inspector
      list
    end

    def restart
      browser.restart
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
      options.fetch(:browser_logger, nil)
    end

    def visit(url)
      @started = true
      browser.visit(url)
    end

    def current_url
      browser.current_url
    end

    def status_code
      browser.status_code
    end

    def html
      browser.body
    end
    alias body html

    def source
      browser.source.to_s
    end

    def title
      browser.title
    end

    def frame_title
      browser.frame_title
    end

    def frame_url
      browser.frame_url
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
      result = browser.evaluate(script, *args.map { |arg| arg.is_a?(Capybara::Apparition::Node) ? arg.native : arg })
      unwrap_script_result(result)
    end

    def evaluate_async_script(script, *args)
      result = browser.evaluate_async(script, session_wait_time, *args.map { |arg| arg.is_a?(Capybara::Apparition::Node) ? arg.native : arg })
      unwrap_script_result(result)
    end

    def execute_script(script, *args)
      browser.execute(script, *args.map { |arg| arg.is_a?(Capybara::Apparition::Node) ? arg.native : arg })
      nil
    end

    def switch_to_frame(frame)
      browser.switch_to_frame(frame)
    end

    def current_window_handle
      browser.window_handle
    end

    def window_handles
      browser.window_handles
    end

    def close_window(handle)
      browser.close_window(handle)
    end

    def open_new_window
      browser.open_new_window
    end

    def switch_to_window(handle)
      browser.switch_to_window(handle)
    end

    def within_window(name, &block)
      browser.within_window(name, &block)
    end

    def no_such_window_error
      NoSuchWindowError
    end

    def reset!
      browser.reset
      # TODO: reset the black/whitelists
      # browser.url_blacklist = options[:url_blacklist] || []
      # browser.url_whitelist = options[:url_whitelist] || []
      @started = false
    end

    def save_screenshot(path, options = {})
      browser.render(path, options)
    end
    alias render save_screenshot

    def render_base64(format = :png, options = {})
      browser.render_base64(format, options)
    end

    def paper_size=(size = {})
      browser.set_paper_size(size)
    end

    # def zoom_factor=(zoom_factor)
    #   TODO: Implement if still necessary
    #   browser.set_zoom_factor(zoom_factor)
    # end

    def resize(width, height)
      browser.resize(width, height, screen: options[:screen_size])
    end
    alias resize_window resize

    def resize_window_to(handle, width, height)
      within_window(handle) do
        resize(width, height)
      end
    end

    def maximize_window(handle)
      within_window(handle) do
        browser.maximize
      end
    end

    def fullscreen_window(handle)
      within_window(handle) do
        browser.fullscreen
      end
    end

    def window_size(handle)
      within_window(handle) do
        evaluate_script('[window.innerWidth, window.innerHeight]')
      end
    end

    def scroll_to(left, top)
      browser.scroll_to(left, top)
    end

    def network_traffic(type = nil)
      browser.network_traffic(type)
    end

    def clear_network_traffic
      browser.clear_network_traffic
    end

    def set_proxy(ip, port, type = 'http', user = nil, password = nil)
      browser.set_proxy(ip, port, type, user, password)
    end

    def headers
      browser.get_headers
    end

    def headers=(headers)
      browser.set_headers(headers)
    end

    def add_headers(headers)
      browser.add_headers(headers)
    end

    def add_header(name, value, options = {})
      browser.add_header({ name => value }, { permanent: true }.merge(options))
    end

    def response_headers
      browser.response_headers.each_with_object({}) { |(key, value), hsh| hsh[key.split('-').map(&:capitalize).join('-')] = value }
    end

    def cookies
      browser.cookies
    end

    def set_cookie(name, value, options = {})
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

    def remove_cookie(name)
      browser.remove_cookie(name)
    end

    def clear_cookies
      browser.clear_cookies
    end

    def cookies_enabled=(flag)
      browser.cookies_enabled = flag
    end

    def clear_memory_cache
      browser.clear_memory_cache
    end

    def basic_authorize(user = nil, password = nil)
      browser.set_http_auth(user, password)
      # credentials = ["#{user}:#{password}"].pack('m*').strip
      # add_header('Authorization', "Basic #{credentials}")
    end

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

      STDERR.puts "Apparition execution paused. Press enter (or run 'kill -CONT #{Process.pid}') to continue."

      signal = false
      old_trap = trap('SIGCONT') do
        signal = true
        STDERR.puts "\nSignal SIGCONT received"
      end
      keyboard = IO.select([read], nil, nil, 1) until keyboard || signal # wait for data on STDIN or signal SIGCONT received

      unless signal
        begin
          input = read.read_nonblock(80) # clear out the read buffer
          puts unless input&.end_with?("\n")
        rescue EOFError, IO::WaitReadable # Ignore problems reading from STDIN.
        end
      end
    ensure
      trap('SIGCONT', old_trap) # Restore the previous signal handler, if there was one.
      STDERR.puts 'Continuing'
    end

    def wait?
      true
    end

    def invalid_element_errors
      [Capybara::Apparition::ObsoleteNode, Capybara::Apparition::MouseEventFailed]
    end

    def go_back
      browser.go_back
    end

    def go_forward
      browser.go_forward
    end

    def refresh
      browser.refresh
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

  private

    def screen_size
      options[:screen_size] || [1366, 768]
    end

    def find_modal(options)
      start_time    = Time.now
      timeout_sec   = options.fetch(:wait) { session_wait_time }
      expect_text   = options[:text]
      expect_regexp = expect_text.is_a?(Regexp) ? expect_text : Regexp.escape(expect_text.to_s)
      begin
        modal_text = browser.modal_message
        found_text ||= modal_text
        raise Capybara::ModalNotFound if modal_text.nil? || (expect_text && !modal_text.match(expect_regexp))
      rescue Capybara::ModalNotFound => e
        if (Time.now - start_time) >= timeout_sec
          raise e, 'Unable to find modal dialog'\
                   "#{" with #{expect_text}" if expect_text}"\
                   "#{", did find modal with #{found_text}" if found_text}"
        end
        sleep(0.5)
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
  end
end
