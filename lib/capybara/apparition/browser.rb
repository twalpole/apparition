# frozen_string_literal: true

require 'capybara/apparition/errors'
require 'capybara/apparition/page'
require 'capybara/apparition/console'
require 'capybara/apparition/dev_tools_protocol/session'
require 'capybara/apparition/browser/page_targets'
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
      @target_threads = []

      initialize_handlers

      command('Target.setDiscoverTargets', discover: true)
      yield self if block_given?
      sleep 1 # allow time to initialize and discover
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

    include PageTargets
    include Header
    include Window
    include Render
    include Cookie
    include Modal
    include Frame
    include Auth

    def reset
      puts "Browser reset" if ENV['DEBUG']
      new_context_id = command('Target.createBrowserContext')['browserContextId']
      join_all_target_threads
      current_pages = page_ids

      command('Target.getTargets')['targetInfos'].select { |ti| ti['type'] == 'page' }.each do |ti|
        client.send_cmd('Target.disposeBrowserContext', browserContextId: ti['browserContextId']).discard_result
        remove_page(ti['targetId'])
      end

      new_target_id = command('Target.createTarget', url: 'about:blank', browserContextId: new_context_id)['targetId']

      wait_for_page(new_target_id)

      mark_page_loaded(new_target_id)

      wait_for_usable_page(new_target_id)
      console.clear

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
        current_page(allow_nil: true)&.add_extension(name)
      end
    end

    def url_whitelist=(whitelist)
      @url_whitelist = whitelist
      each_page { |page| page.url_whitelist = whitelist }
    end

    def url_blacklist=(blacklist)
      @url_blacklist = blacklist
      each_page { |page| page.url_blacklist = blacklist }
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

    def console_messages(type = nil)
      console.messages(type)
    end

  private

    def log(message)
      @logger&.puts message if ENV['DEBUG']
    end

    def initialize_handlers
      initialize_target_handlers
    end
  end
end
