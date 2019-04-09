# frozen_string_literal: true

require 'capybara/apparition/errors'
require 'capybara/apparition/page'
require 'capybara/apparition/console'
require 'capybara/apparition/dev_tools_protocol/session'
require 'capybara/apparition/browser/header'
require 'capybara/apparition/browser/window'
require 'capybara/apparition/browser/render'
require 'capybara/apparition/browser/cookie'
require 'capybara/apparition/browser/modal'
require 'capybara/apparition/browser/frame'
require 'capybara/apparition/browser/auth'
require 'json'
require 'time'

module Capybara::Apparition
  class Browser
    attr_reader :client, :paper_size, :zoom_factor, :console, :proxy_auth
    extend Forwardable

    delegate %i[visit current_url status_code
                title frame_title frame_url
                find scroll_to clear_network_traffic
                evaluate evaluate_async execute
                fullscreen maximize
                response_headers
                go_back go_forward refresh] => :current_page

    def initialize(client, logger = nil)
      @client = client
      @current_page_handle = nil
      @pages = {}
      @context_id = nil
      @js_errors = true
      @ignore_https_errors = false
      @logger = logger
      @console = Console.new(logger)
      @proxy_auth = nil

      initialize_handlers

      command('Target.setDiscoverTargets', discover: true)
      yield self if block_given?
      reset
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

    def body
      current_page.content
    end

    def source
      # Is this still useful?
      # command 'source'
    end

    def click_coordinates(x, y)
      current_page.click_at(x, y)
    end

    include Header
    include Window
    include Render
    include Cookie
    include Modal
    include Frame
    include Auth

    def reset
      new_context_id = command('Target.createBrowserContext')['browserContextId']
      current_pages = @pages.keys

      new_target_response = client.send_cmd('Target.createTarget', url: 'about:blank', browserContextId: new_context_id)
      @pages.each do |id, page|
        begin
          client.send_cmd('Target.disposeBrowserContext', browserContextId: page.browser_context_id).discard_result
        rescue WrongWorld
          puts 'Unknown browserContextId'
        end
        @pages.delete(id)
      end

      new_target_id = new_target_response['targetId']

      session_id = command('Target.attachToTarget', targetId: new_target_id)['sessionId']
      session = Capybara::Apparition::DevToolsProtocol::Session.new(self, client, session_id)

      @pages[new_target_id] = Page.create(self, session, new_target_id, new_context_id,
                                          ignore_https_errors: ignore_https_errors,
                                          js_errors: js_errors, extensions: @extensions,
                                          url_blacklist: @url_blacklist,
                                          url_whitelist: @url_whitelist) # .inherit(@info.delete('inherit'))
      @pages[new_target_id].send(:main_frame).loaded!

      timer = Capybara::Helpers.timer(expire_in: 10)
      until @pages[new_target_id].usable?
        if timer.expired?
          puts 'Timedout waiting for reset'
          raise TimeoutError.new('reset')
        end
        sleep 0.01
      end
      console.clear
      @current_page_handle = new_target_id
      true
    end

    def refresh_pages(opener:)
      new_pages = command('Target.getTargets')['targetInfos'].select do |ti|
        (ti['openerId'] == opener.target_id) && (ti['type'] == 'page') && (ti['attached'] == false)
      end
      sessions = new_pages.map do |page|
        target_id = page['targetId']
        session_result = client.send_cmd('Target.attachToTarget', targetId: target_id)
        [target_id, session_result]
      end

      sessions = sessions.map do |(target_id, session_result)|
        session = Capybara::Apparition::DevToolsProtocol::Session.new(self, client, session_result.result['sessionId'])
        [target_id, session]
      end

      sessions.each do |(_target_id, session)|
        session.async_commands 'Page.enable', 'Network.enable', 'Runtime.enable', 'Security.enable', 'DOM.enable'
      end

      # sessions.each do |(target_id, session_result)|
      #   session = Capybara::Apparition::DevToolsProtocol::Session.new(self, client, session_result.result['sessionId'])
      sessions.each do |(target_id, session)|
        page_options = { ignore_https_errors: ignore_https_errors, js_errors: js_errors,
                         url_blacklist: @url_blacklist, url_whitelist: @url_whitelist }
        new_page = Page.create(self, session, target_id, opener.browser_context_id, page_options).inherit(opener)
        @pages[target_id] = new_page
      end

      # new_pages.each do |page|
      #   target_id = page['targetId']
      #   session_id = command('Target.attachToTarget', targetId: target_id)['sessionId']
      #   session = Capybara::Apparition::DevToolsProtocol::Session.new(self, client, session_id)
      #   page_options = { ignore_https_errors: ignore_https_errors, js_errors: js_errors,
      #                  url_blacklist: @url_blacklist, url_whitelist: @url_whitelist }
      #   new_page = Page.create(self, session, page['targetId'], opener.browser_context_id, page_options).inherit(opener)
      #   @pages[target_id] = new_page
      # end
    end

    def resize(width, height, screen: nil)
      current_page.set_viewport width: width, height: height, screen: screen
    end

    def network_traffic(type = nil)
      case type
      when :blocked
        current_page.network_traffic.select(&:blocked?)
      else
        current_page.network_traffic
      end
    end

    attr_accessor :js_errors, :ignore_https_errors

    def extensions=(filenames)
      @extensions = filenames
      Array(filenames).each do |name|
        current_page(allow_nil: true)&.add_extension(name)
      end
    end

    def url_whitelist=(whitelist)
      @url_whitelist = whitelist
      @pages.each do |_id, page|
        page.url_whitelist = whitelist
      end
    end

    def url_blacklist=(blacklist)
      @url_blacklist = blacklist
      @pages.each do |_id, page|
        page.url_blacklist = blacklist
      end
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

    def current_page(allow_nil: false)
      @pages[@current_page_handle] || begin
        puts "No current page: #{@current_page_handle} : #{caller}" if ENV['DEBUG']
        @current_page_handle = nil
        raise NoSuchWindowError unless allow_nil

        @current_page_handle
      end
    end

    def console_messages(type = nil)
      console.messages(type)
    end

  private

    def log(message)
      @logger&.puts message if ENV['DEBUG']
    end

    # KEY_ALIASES = {
    #   command: :Meta,
    #   equals: :Equal,
    #   control: :Control,
    #   ctrl: :Control,
    #   multiply: 'numpad*',
    #   add: 'numpad+',
    #   divide: 'numpad/',
    #   subtract: 'numpad-',
    #   decimal: 'numpad.',
    #   left: 'ArrowLeft',
    #   right: 'ArrowRight',
    #   down: 'ArrowDown',
    #   up: 'ArrowUp'
    # }.freeze
    #
    # def normalize_keys(keys)
    #   keys.map do |key_desc|
    #     case key_desc
    #     when Array
    #       # [:Shift, "s"] => { modifier: "shift", keys: "S" }
    #       # [:Shift, "string"] => { modifier: "shift", keys: "STRING" }
    #       # [:Ctrl, :Left] => { modifier: "ctrl", key: 'Left' }
    #       # [:Ctrl, :Shift, :Left] => { modifier: "ctrl,shift", key: 'Left' }
    #       # [:Ctrl, :Left, :Left] => { modifier: "ctrl", key: [:Left, :Left] }
    #       keys_chunks = key_desc.chunk do |k|
    #         k.is_a?(Symbol) && %w[shift ctrl control alt meta command].include?(k.to_s.downcase)
    #       end
    #       modifiers = modifiers_from_chunks(keys_chunks)
    #       letters = normalize_keys(_keys.next[1].map { |k| k.is_a?(String) ? k.upcase : k })
    #       { modifier: modifiers, keys: letters }
    #     when Symbol
    #       symbol_to_desc(key_desc)
    #     when String
    #       key_desc # Plain string, nothing to do
    #     end
    #   end
    # end
    #
    # def modifiers_from_chunks(chunks)
    #   if chunks.peek[0]
    #     chunks.next[1].map do |k|
    #       k = k.to_s.downcase
    #       k = 'control' if k == 'ctrl'
    #       k = 'meta' if k == 'command'
    #       k
    #     end.join(',')
    #   else
    #     ''
    #   end
    # end
    #
    # def symbol_to_desc(symbol)
    #   if symbol == :space
    #     res = ' '
    #   else
    #     key = KEY_ALIASES.fetch(symbol.downcase, symbol)
    #     if (match = key.to_s.match(/numpad(.)/))
    #       res = { keys: match[1], modifier: 'keypad' }
    #     elsif !/^[A-Z]/.match?(key)
    #       key = key.to_s.split('_').map(&:capitalize).join
    #     end
    #   end
    #   res || { key: key }
    # end

    def initialize_handlers
      # @client.on 'Target.targetCreated' do |info|
      #   byebug
      #   puts "Target Created Info: #{info}" if ENV['DEBUG']
      #   target_info = info['targetInfo']
      #   if !@pages.key?(target_info['targetId'])
      #     @pages.add(target_info['targetId'], target_info)
      #     puts "**** Target Added #{info}" if ENV['DEBUG']
      #   elsif ENV['DEBUG']
      #     puts "Target already existed #{info}"
      #   end
      #   @current_page_handle ||= target_info['targetId'] if target_info['type'] == 'page'
      # end

      @client.on 'Target.targetDestroyed' do |info|
        puts "**** Target Destroyed Info: #{info}" if ENV['DEBUG']
        @pages.delete(info['targetId'])
      end

      # @client.on 'Target.targetInfoChanged' do |info|
      #   byebug
      #   puts "**** Target Info Changed: #{info}" if ENV['DEBUG']
      #   target_info = info['targetInfo']
      #   page = @pages[target_info['targetId']]
      #   if page
      #     page.update(target_info)
      #   else
      #     puts '****No target for the info change- creating****' if ENV['DEBUG']
      #     @pages.add(target_info['targetId'], target_info)
      #   end
      # end
    end
  end
end
