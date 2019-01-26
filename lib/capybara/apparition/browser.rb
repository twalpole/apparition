# frozen_string_literal: true

require 'capybara/apparition/errors'
require 'capybara/apparition/dev_tools_protocol/target_manager'
require 'capybara/apparition/page'
require 'json'
require 'time'

module Capybara::Apparition
  class Browser
    attr_reader :client, :logger, :paper_size, :zoom_factor

    def initialize(client, logger = nil)
      @client = client
      @logger = logger
      @current_page_handle = nil
      @targets = Capybara::Apparition::DevToolsProtocol::TargetManager.new
      @context_id = nil
      @js_errors = true
      @ignore_https_errors = false

      initialize_handlers

      command('Target.setDiscoverTargets', discover: true)
      while @current_page_handle.nil?
        puts 'waiting for target...'
        sleep 0.1
      end
    end

    def restart
      puts 'handle client restart'
      # client.restart

      self.debug = @debug if defined?(@debug)
      self.js_errors = @js_errors if defined?(@js_errors)
      self.zoom_factor = @zoom_factor if defined?(@zoom_factor)
      self.extensions = @extensions if @extensions
      current_page.clear_network_traffic
    end

    def visit(url)
      current_page.visit url
    end

    def current_url
      current_page.current_url
    end

    def status_code
      current_page.status_code
    end

    def body
      current_page.content
    end

    def source
      # Is this still useful?
      # command 'source'
    end

    def title
      # Updated info doesn't have correct title when changed programmatically
      # current_target.title
      current_page.title
    end

    def frame_title
      current_page.frame_title
    end

    def frame_url
      current_page.frame_url
    end

    def find(method, selector)
      current_page.find(method, selector)
    end

    def click_coordinates(x, y)
      current_page.click_at(x, y)
    end

    def evaluate(script, *args)
      current_page.evaluate(script, *args)
    end

    def evaluate_async(script, wait_time, *args)
      current_page.evaluate_async(script, wait_time, *args)
    end

    def execute(script, *args)
      current_page.execute(script, *args)
    end

    def switch_to_frame(frame)
      case frame
      when Capybara::Node::Base
        current_page.push_frame(frame)
      when :parent
        current_page.pop_frame
      when :top
        current_page.pop_frame(top: true)
      end
    end

    def window_handle
      @current_page_handle
    end

    def window_handles
      @targets.window_handles
    end

    def switch_to_window(handle)
      target = @targets.get(handle)
      raise NoSuchWindowError unless target&.page

      target.page.wait_for_loaded
      @current_page_handle = handle
    end

    def open_new_window
      context_id = @context_id || current_target.info['browserContextId']
      info = command('Target.createTarget', url: 'about:blank', browserContextId: context_id)
      target_id = info['targetId']
      target = DevToolsProtocol::Target.new(self, info.merge('type' => 'page', 'inherit' => current_page))
      target.page # Ensure page object construction happens
      @targets.add(target_id, target)
      target_id
    end

    def close_window(handle)
      @targets.delete(handle)
      @current_page_handle = nil if @current_page_handle == handle
      command('Target.closeTarget', targetId: handle)
    end

    def within_window(locator)
      original = window_handle
      handle = find_window_handle(locator)
      switch_to_window(handle)
      yield
    ensure
      switch_to_window(original)
    end

    def reset
      command('Target.disposeBrowserContext', browserContextId: @context_id) if @context_id

      @context_id = command('Target.createBrowserContext')['browserContextId']
      target_id = command('Target.createTarget', url: 'about:blank', browserContextId: @context_id)['targetId']

      start = Time.now
      until @targets.get(target_id)&.page&.usable?
        if Time.now - start > 5
          puts 'Timedout waiting for reset'
          # byebug
          raise TimeoutError.new('reset')
        end
        sleep 0.01
      end
      @current_page_handle = target_id
      true
    end

    def scroll_to(left, top)
      current_page.scroll_to(left, top)
    end

    def render(path, options = {})
      check_render_options!(options, path)
      img_data = current_page.render(options)
      File.open(path, 'wb') { |f| f.write(Base64.decode64(img_data)) }
    end

    def render_base64(options = {})
      check_render_options!(options)
      current_page.render(options)
    end

    attr_writer :zoom_factor

    def paper_size=(size)
      @paper_size = if size.is_a? Hash
        size
      else
        PAPER_SIZES.fetch(size) do
          raise_errors ArgumentError, "Unknwon paper size: #{size}"
        end
      end
    end

    def resize(width, height, screen: nil)
      current_page.set_viewport width: width, height: height, screen: screen
    end

    def fullscreen
      current_page.fullscreen
    end

    def maximize
      current_page.maximize
    end

    def network_traffic(type = nil)
      case type
      when :blocked
        current_page.network_traffic.select(&:blocked?)
      else
        current_page.network_traffic
      end
    end

    def clear_network_traffic
      current_page.clear_network_traffic
    end

    def set_proxy(ip, port, type, user, password)
      args = [ip, port, type]
      args << user if user
      args << password if password
      # TODO: Implement via CDP if possible
      # command('set_proxy', *args)
    end

    def get_headers
      current_page.extra_headers
    end

    def set_headers(headers)
      @targets.pages.each do |page|
        page.perm_headers = headers
        page.temp_headers = {}
        page.temp_no_redirect_headers = {}
        page.update_headers
      end
    end

    def add_headers(headers)
      current_page.perm_headers.merge! headers
      current_page.update_headers
    end

    def add_header(header, permanent: true, **_options)
      if permanent == true
        @targets.pages.each do |page|
          page.perm_headers.merge! header
          page.update_headers
        end
      else
        if permanent.to_s == 'no_redirect'
          current_page.temp_no_redirect_headers.merge! header
        else
          current_page.temp_headers.merge! header
        end
        current_page.update_headers
      end
    end

    def response_headers
      current_page.response_headers
    end

    def cookies
      current_page.command('Network.getCookies')['cookies'].each_with_object({}) do |c, h|
        h[c['name']] = Cookie.new(c)
      end
    end

    def set_cookie(cookie)
      if cookie[:expires]
        # cookie[:expires] = cookie[:expires].to_i * 1000
        cookie[:expires] = cookie[:expires].to_i
      end

      current_page.command('Network.setCookie', cookie)
    end

    def remove_cookie(name)
      current_page.command('Network.deleteCookies', name: name, url: current_url)
    end

    def clear_cookies
      current_page.command('Network.clearBrowserCookies')
    end

    def cookies_enabled=(flag)
      current_page.command('Emulation.setDocumentCookieDisabled', disabled: !flag)
    end

    def set_http_auth(user = nil, password = nil)
      current_page.credentials = if user.nil? && password.nil?
        nil
      else
        { username: user, password: password }
      end
    end

    attr_accessor :js_errors, :ignore_https_errors

    def extensions=(filenames)
      @extensions = filenames
      Array(filenames).each do |name|
        begin
          current_page.command('Page.addScriptToEvaluateOnNewDocument', source: File.read(name))
        rescue Errno::ENOENT
          raise ::Capybara::Apparition::BrowserError.new('name' => "Unable to load extension: #{name}", 'args' => nil)
        end
      end
    end

    def url_whitelist=(whitelist)
      current_page&.url_whitelist = whitelist
    end

    def url_blacklist=(blacklist)
      current_page&.url_blacklist = blacklist
    end

    attr_writer :debug

    def clear_memory_cache
      current_page.command('Network.clearBrowserCache')
    end

    def command(name, params = {})
      result = client.send_cmd(name, params).result
      log result

      result || raise(Capybara::Apparition::ObsoleteNode.new(nil, nil))
    rescue DeadClient
      restart
      raise
    end

    def command_for_session(session_id, name, params)
      client.send_cmd_to_session(session_id, name, params)
    rescue DeadClient
      restart
      raise
    end

    def go_back
      current_page.go_back
    end

    def go_forward
      current_page.go_forward
    end

    def refresh
      current_page.refresh
    end

    def accept_alert
      current_page.add_modal(alert: true)
    end

    def accept_confirm
      current_page.add_modal(confirm: true)
    end

    def dismiss_confirm
      current_page.add_modal(confirm: false)
    end

    def accept_prompt(response)
      current_page.add_modal(prompt: response)
    end

    def dismiss_prompt
      current_page.add_modal(prompt: false)
    end

    def modal_message
      current_page.modal_messages.shift
    end

    def current_page
      current_target.page
    end

  private

    def current_target
      @targets.get(@current_page_handle) || begin
        puts "No current page: #{@current_page_handle}"
        @current_page_handle = nil
        raise NoSuchWindowError
      end
    end

    def log(message)
      logger&.puts message
    end

    def check_render_options!(options, path = nil)
      options[:format] ||= File.extname(path).downcase[1..-1] if path
      options[:format] = :jpeg if options[:format].to_s == 'jpg'
      options[:full] = !!options[:full]
      return unless options[:full] && options.key?(:selector)

      warn "Ignoring :selector in #render since :full => true was given at #{caller(1..1)}"
      options.delete(:selector)
    end

    def find_window_handle(locator)
      return locator if window_handles.include? locator

      window_handles.each do |handle|
        switch_to_window(handle)
        return handle if evaluate('window.name') == locator
      end
      raise NoSuchWindowError
    end

    KEY_ALIASES = {
      command: :Meta,
      equals: :Equal,
      control: :Control,
      ctrl: :Control,
      multiply: 'numpad*',
      add: 'numpad+',
      divide: 'numpad/',
      subtract: 'numpad-',
      decimal: 'numpad.',
      left: 'ArrowLeft',
      right: 'ArrowRight',
      down: 'ArrowDown',
      up: 'ArrowUp'
    }.freeze

    def normalize_keys(keys)
      keys.map do |key_desc|
        case key_desc
        when Array
          # [:Shift, "s"] => { modifier: "shift", keys: "S" }
          # [:Shift, "string"] => { modifier: "shift", keys: "STRING" }
          # [:Ctrl, :Left] => { modifier: "ctrl", key: 'Left' }
          # [:Ctrl, :Shift, :Left] => { modifier: "ctrl,shift", key: 'Left' }
          # [:Ctrl, :Left, :Left] => { modifier: "ctrl", key: [:Left, :Left] }
          keys_chunks = key_desc.chunk do |k|
            k.is_a?(Symbol) && %w[shift ctrl control alt meta command].include?(k.to_s.downcase)
          end
          modifiers = modifiers_from_chunks(keys_chunks)
          letters = normalize_keys(_keys.next[1].map { |k| k.is_a?(String) ? k.upcase : k })
          { modifier: modifiers, keys: letters }
        when Symbol
          symbol_to_desc(key_desc)
        when String
          key_desc # Plain string, nothing to do
        end
      end
    end

    def modifiers_from_chunks(chunks)
      if chunks.peek[0]
        chunks.next[1].map do |k|
          k = k.to_s.downcase
          k = 'control' if k == 'ctrl'
          k = 'meta' if k == 'command'
          k
        end.join(',')
      else
        ''
      end
    end

    def symbol_to_desc(symbol)
      if symbol == :space
        res = ' '
      else
        key = KEY_ALIASES.fetch(symbol.downcase, symbol)
        if (match = key.to_s.match(/numpad(.)/))
          res = { keys: match[1], modifier: 'keypad' }
        elsif !/^[A-Z]/.match?(key)
          key = key.to_s.split('_').map(&:capitalize).join
        end
      end
      res || { key: key }
    end

    def initialize_handlers
      @client.on 'Target.targetCreated' do |info|
        puts "Target Created Info: #{info}" if ENV['DEBUG']
        target_info = info['targetInfo']
        if !@targets.target?(target_info['targetId'])
          @targets.add(target_info['targetId'], DevToolsProtocol::Target.new(self, target_info))
          puts "**** Target Added #{info}" if ENV['DEBUG']
        elsif ENV['DEBUG']
          puts "Target already existed #{info}"
        end
        @current_page_handle ||= target_info['targetId'] if target_info['type'] == 'page'
      end

      @client.on 'Target.targetDestroyed' do |info|
        puts "**** Target Destroyed Info: #{info}" if ENV['DEBUG']
        @targets.delete(info['targetId'])
      end

      @client.on 'Target.targetInfoChanged' do |info|
        puts "**** Target Info Changed: #{info}" if ENV['DEBUG']
        target_info = info['targetInfo']
        target = @targets.get(target_info['targetId'])
        if target
          target.info.merge!(target_info)
        else
          puts '****No target for the info change- creating****' if ENV['DEBUG']
          @targets.add(target_info['targetId'], DevToolsProtocol::Target.new(self, target_info))
        end
      end
    end

    PAPER_SIZES = {
      'A3' => { width: 11.69, height: 16.53 },
      'A4' => { width: 8.27, height: 11.69 },
      'A5' => { width: 5.83, height: 8.27 },
      'Legal' => { width: 8.5, height: 14 },
      'Letter' => { width: 8.5, height: 11 },
      'Tabloid' => { width: 11, height: 17 },
      'Ledger' => { width: 17, height: 11 }
    }.freeze
  end
end
