# frozen_string_literal: true

require 'capybara/apparition/errors'
require 'capybara/apparition/dev_tools_protocol/target_manager'
require 'capybara/apparition/page'
require 'capybara/apparition/console'
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
      @targets = Capybara::Apparition::DevToolsProtocol::TargetManager.new(self)
      @context_id = nil
      @js_errors = true
      @ignore_https_errors = false
      @logger = logger
      @console = Console.new(logger)
      @proxy_auth = nil

      initialize_handlers

      command('Target.setDiscoverTargets', discover: true)
      while @current_page_handle.nil?
        puts 'waiting for target...'
        sleep 0.1
      end
      @context_id = current_target.context_id
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
      current_page_targets = @targets.of_type('page').values

      new_context_id = command('Target.createBrowserContext')['browserContextId']
      new_target_response = client.send_cmd('Target.createTarget', url: 'about:blank', browserContextId: new_context_id)

      current_page_targets.each do |target|
        begin
          client.send_cmd('Target.disposeBrowserContext', browserContextId: target.context_id).discard_result
        rescue WrongWorld
          puts 'Unknown browserContextId'
        end
        @targets.delete(target.id)
      end

      new_target_id = new_target_response.result['targetId']

      timer = Capybara::Helpers.timer(expire_in: 10)
      until @targets.get(new_target_id)&.page&.usable?
        if timer.expired?
          puts 'Timedout waiting for reset'
          raise TimeoutError.new('reset')
        end
        sleep 0.01
      end
      @current_page_handle = new_target_id
      true
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

    def current_page
      current_target.page
    end

    def console_messages(type = nil)
      console.messages(type)
    end

  private

    def current_target
      @targets.get(@current_page_handle) || begin
        puts "No current page: #{@current_page_handle}"
        puts caller
        @current_page_handle = nil
        raise NoSuchWindowError
      end
    end

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
      @client.on 'Target.targetCreated' do |info|
        puts "Target Created Info: #{info}" if ENV['DEBUG']
        target_info = info['targetInfo']
        if !@targets.target?(target_info['targetId'])
          # @targets.add(target_info['targetId'], DevToolsProtocol::Target.new(self, target_info))
          @targets.add(target_info['targetId'], target_info)
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
          target.update(target_info)
        else
          puts '****No target for the info change- creating****' if ENV['DEBUG']
          @targets.add(target_info['targetId'], target_info)
        end
      end
    end
  end
end
