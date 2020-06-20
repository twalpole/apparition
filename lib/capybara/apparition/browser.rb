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
require 'capybara/apparition/browser/page_manager'
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
      @pages = PageManager.new(self)
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
      # puts 'handle client restart'
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
      new_target_response = client.send_cmd('Target.createTarget', url: 'about:blank', browserContextId: new_context_id)

      @pages.reset

      new_target_id = new_target_response['targetId']

      session_id = command('Target.attachToTarget', targetId: new_target_id)['sessionId']
      session = Capybara::Apparition::DevToolsProtocol::Session.new(self, client, session_id)

      @pages.create(new_target_id, session, new_context_id,
                    ignore_https_errors: ignore_https_errors,
                    js_errors: js_errors, extensions: @extensions,
                    url_blacklist: @url_blacklist,
                    url_whitelist: @url_whitelist).send(:main_frame).loaded!

      timer = Capybara::Helpers.timer(expire_in: 10)
      until @pages[new_target_id].usable?
        if timer.expired?
          puts 'Timedout waiting for reset'
          raise TimeoutError, 'reset'
        end
        sleep 0.01
      end
      console.clear
      @current_page_handle = new_target_id
      true
    end

    def refresh_pages(opener:)
      @pages.refresh(opener: opener,
                     ignore_https_errors: ignore_https_errors,
                     js_errors: js_errors,
                     url_blacklist: @url_blacklist,
                     url_whitelist: @url_whitelist)
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
      @url_whitelist = @pages.whitelist = whitelist
    end

    def url_blacklist=(blacklist)
      @url_blacklist = @pages.blacklist = blacklist
    end

    attr_writer :debug

    def clear_memory_cache
      current_page.command('Network.clearBrowserCache')
    end

    def command(name, **params)
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
      return unless @logger && ENV['DEBUG']

      if @logger.respond_to?(:puts)
        @logger.puts(message)
      else
        @logger.debug(message)
      end
    end

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

      @client.on 'Target.targetDestroyed' do |target_id:, **info|
        puts "**** Target Destroyed Info: #{target_id} - #{info}" if ENV['DEBUG']
        @pages.delete(target_id)
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
