# frozen_string_literal: true

require 'capybara/apparition/frame_manager'
require 'capybara/apparition/mouse'
require 'capybara/apparition/keyboard'

module Capybara::Apparition
  class Page
    attr_reader :modal_messages
    attr_reader :mouse, :keyboard
    attr_reader :viewport_size
    attr_accessor :perm_headers, :temp_headers
    attr_reader :network_traffic

    def self.create(browser, session, id, ignore_https_errors, screenshot_task_queue)
      session.command 'Page.enable'
      session.command 'Page.setLifecycleEventsEnabled', enabled: true
      session.command 'Page.setDownloadBehavior', behavior: 'allow', downloadPath: Capybara.save_path

      page = Page.new(browser, session, id, ignore_https_errors, screenshot_task_queue)
      session.command 'Network.enable'
      session.command 'Runtime.enable'
      # sleep 1
      session.command 'Security.enable'

      session.command 'Security.setOverrideCertificateErrors', override: true if ignore_https_errors

      session.command 'DOM.enable'

      # Initialize default page size.
      # page.set_viewport width: 800, height: 600

      # page.visit 'about:blank'
      page
    end

    def initialize(browser, session, id, _ignore_https_errors, _screenshot_task_queue)
      @target_id = id
      @browser = browser
      @session = session
      @keyboard = Keyboard.new(self)
      @mouse = Mouse.new(self, @keyboard)
      @modals = []
      @modal_messages = []
      @frames = Capybara::Apparition::FrameManager.new(id)
      @response_headers = {}
      @status_code = nil
      @url_blacklist = []
      @url_whitelist = []
      @auth_attempts = []
      @perm_headers = {}
      @temp_headers = {}
      @viewport_size = nil
      @network_traffic = []

      register_event_handlers


      # this._keyboard = new Keyboard(client);
      # this._mouse = new Mouse(client, this._keyboard);
      # this._touchscreen = new Touchscreen(client, this._keyboard);
      # this._frameManager = new FrameManager(client, this._mouse, this._touchscreen);
      # this._networkManager = new NetworkManager(client);
      # this._emulationManager = new EmulationManager(client);
      # this._tracing = new Tracing(client);
      # /** @type {!Map<string, function>} */
      # this._pageBindings = new Map();
      # this._ignoreHTTPSErrors = ignoreHTTPSErrors;
      #
      # this._screenshotTaskQueue = screenshotTaskQueue;
      #
      # this._frameManager.on(FrameManager.Events.FrameAttached, event => this.emit(Page.Events.FrameAttached, event));
      # this._frameManager.on(FrameManager.Events.FrameDetached, event => this.emit(Page.Events.FrameDetached, event));
      # this._frameManager.on(FrameManager.Events.FrameNavigated, event => this.emit(Page.Events.FrameNavigated, event));
      #
      # this._networkManager.on(NetworkManager.Events.Request, event => this.emit(Page.Events.Request, event));
      # this._networkManager.on(NetworkManager.Events.Response, event => this.emit(Page.Events.Response, event));
      # this._networkManager.on(NetworkManager.Events.RequestFailed, event => this.emit(Page.Events.RequestFailed, event));
      # this._networkManager.on(NetworkManager.Events.RequestFinished, event => this.emit(Page.Events.RequestFinished, event));
      #
      # client.on('Page.loadEventFired', event => this.emit(Page.Events.Load));
      # client.on('Runtime.consoleAPICalled', event => this._onConsoleAPI(event));
      # client.on('Page.javascriptDialogOpening', event => this._onDialog(event));
      # client.on('Runtime.exceptionThrown', exception => this._handleException(exception.exceptionDetails));
      # client.on('Security.certificateError', event => this._onCertificateError(event));
      # client.on('Inspector.targetCrashed', event => this._onTargetCrashed());
    end

    def usable?
      !!current_frame&.context_id
    end

    def reset
      @modals.clear
      @modal_messages.clear
      @response_headers = {}
      @status_code = nil
      @auth_attempts = []
      @perm_headers = {}
    end

    def add_modal(modal_response)
      @last_modal_message = nil
      @modals.push(modal_response)
    end

    def credentials=(creds)
      @credentials = creds
      setup_network_interception
    end

    def url_blacklist=(blacklist)
      @url_blacklist = blacklist
      setup_network_blocking
    end

    def url_whitelist=(whitelist)
      @url_whitelist = whitelist
      setup_network_blocking
    end

    def clear_network_traffic
      @network_traffic = []
    end

    def scroll_to(left, top)
      wait_for_loaded
      execute('window.scrollTo(arguments[0], arguments[1])', left, top)
    end

    def click_at(x, y)
      wait_for_loaded
      @mouse.click_at(x: x, y: y)
    end

    def current_state
      main_frame.state
    end

    def current_frame_offset
      return { x: 0, y: 0 } if current_frame.id == main_frame.id

      result = command('DOM.getBoxModel', objectId: current_frame.element_id)
      x, y = result['model']['content']
      { x: x, y: y }
    end

    def render(options)
      wait_for_loaded
      res = command('Page.captureScreenshot', options)
      res['data']
    end

    def push_frame(frame_el)
      node = command('DOM.describeNode', objectId: frame_el.base.id)
      frame_id = node['node']['frameId']
      start = Time.now
      while (frame = @frames.get(frame_id)).nil? || frame.loading?
        # Wait for the frame creation messages to be processed
        byebug if Time.now - start > 10
        #
        # raise TimeoutError if Time.now - start > 10
        sleep 0.1
      end
      return unless frame
      frame.element_id = frame_el.base.id
      @frames.push_frame(frame.id)
      frame
    end

    def pop_frame(top: false)
      @frames.pop_frame(top: top)
    end

    def find(method, selector)
      wait_for_loaded
      js_escaped_selector = selector.gsub('\\', '\\\\\\').gsub('"', '\"')
      result = if method == :css
        _raw_evaluate("Array.from(document.querySelectorAll(\"#{js_escaped_selector}\"));")
      else
        _raw_evaluate("
          (function(){
            const xpath = document.evaluate(\"#{js_escaped_selector}\", document, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            let results = [];
            for (let i=0; i < xpath.snapshotLength; i++){
              results.push(xpath.snapshotItem(i))
            };
            return results;
          })()")
      end
      (result || []).map { |r_o| [self, r_o['objectId']] }
    rescue ::Capybara::Apparition::BrowserError => e
      raise unless e.name =~ /is not a valid (XPath expression|selector)/

      raise Capybara::Apparition::InvalidSelector, [method, selector]
    end

    def execute(script, *args)
      wait_for_loaded
      _execute_script("function(){ #{script} }", *args)
      nil
    end

    def evaluate(script, *args)
      wait_for_loaded
      _execute_script("function(){ return #{script} }", *args)
    end

    def evaluate_async(script, _wait_time, *args)
      wait_for_loaded
      _execute_script("function(){
        var args = Array.prototype.slice.call(arguments);
        return new Promise((resolve, reject)=>{
          args.push(resolve);
          var fn = function(){ #{script} };
          fn.apply(this, args);
        });
      }", *args)
    end

    def refresh
      wait_for_loaded
      command('Page.reload')
    end

    def go_back
      wait_for_loaded
      go_history(-1)
    end

    def go_forward
      wait_for_loaded
      go_history(+1)
    end

    attr_reader :response_headers

    attr_reader :status_code


    def wait_for_loaded(allow_obsolete: false)
      start = Time.now
      cf = current_frame
      until cf.usable? || (allow_obsolete && cf.obsolete?)
        byebug if Time.now - start > 5
        #
        # raise TimeoutError if Time.now - start > 10
        sleep 0.05
      end
    end

    def content
      wait_for_loaded
      _raw_evaluate("(function(){
        let val = '';
        if (document.doctype)
          val = new XMLSerializer().serializeToString(document.doctype);
        if (document.documentElement)
          val += document.documentElement.outerHTML;
        return val;
      })()")
    end

    def visit(url)
      wait_for_loaded
      @status_code = nil
      navigate_opts = { url: url, transitionType: "typed" }
      navigate_opts[:referrer] = extra_headers['Referer'] if extra_headers['Referer']
      response = command('Page.navigate', navigate_opts)
      main_frame.loader_id = response['loaderId']
      wait_for_loaded
    end

    def current_url
      wait_for_loaded
      _raw_evaluate('window.location.href', context_id: main_frame.context_id)
    end

    def frame_url
      wait_for_loaded
      _raw_evaluate('window.location.href')
    end

    def set_viewport(width:, height:, screen: nil)
      wait_for_loaded
      @viewport_size = { width: width, height: height }
      begin
        result = @browser.command('Browser.getWindowForTarget', targetId: @target_id)
        @browser.command('Browser.setWindowBounds', windowId: result['windowId'], bounds: { width: width, height: height })
      rescue
        # IF headless there is no window and Browser.getWindowForTarget fails
      end
      metrics = {
        mobile: false,
        width: width,
        height: height,
        deviceScaleFactor: 1
      }
      metrics[:screenWidth], metrics[:screenHeight] = *screen if screen

      command('Emulation.setDeviceMetricsOverride', metrics)
    end

    def fullscreen
      result = @browser.command('Browser.getWindowForTarget', targetId: @target_id)
      @browser.command('Browser.setWindowBounds', windowId: result['windowId'], bounds: { windowState: 'fullscreen' })
    end

    def maximize
      screen_width, screen_height = *evaluate('[window.screen.width, window.screen.height]')
      set_viewport(width: screen_width, height: screen_height)

      result = @browser.command('Browser.getWindowForTarget', targetId: @target_id)
      @browser.command('Browser.setWindowBounds', windowId: result['windowId'], bounds: { windowState: 'maximized' })
    end

    def title
      wait_for_loaded
      _raw_evaluate('document.title', context_id: main_frame.context_id)
    end

    def frame_title
      wait_for_loaded
      _raw_evaluate('document.title')
    end

    def command(name, params = {})
      @browser.command_for_session(@session.session_id, name, params)
    end

    def extra_headers
      temp_headers.merge perm_headers
    end

    def update_headers
      if extra_headers['User-Agent']
        command('Network.setUserAgentOverride', userAgent: extra_headers['User-Agent'])
      end
      command('Network.setExtraHTTPHeaders', headers: extra_headers)
    end

  private

    def register_event_handlers
      @session.on 'Page.javascriptDialogOpening' do |params|
        type = params['type'].to_sym
        if type == :beforeunload
          accept = true
        else
          # params has 'url', 'message', 'type', 'defaultPrompt'
          @modal_messages.push(params['message'])
          response = @modals.pop
          raise "Unexpected #{type} modal" if !response || !response.key?(type)

          accept = response[type]
        end

        if type == :prompt
          case accept
          when false
            command('Page.handleJavaScriptDialog', accept: false)
          when nil
            command('Page.handleJavaScriptDialog', accept: true, promptText: params['defaultPrompt'])
          else
            command('Page.handleJavaScriptDialog', accept: true, promptText: accept)
          end
        else
          command('Page.handleJavaScriptDialog', accept: accept)
        end
      end

      @session.on 'Page.windowOpen' do |params|
        puts "**** windowOpen was called with: #{params}" if ENV['DEBUG']
      end

      @session.on 'Page.frameAttached' do |params|
        puts "**** frameAttached called with #{params}" if ENV['DEBUG']
        # @frames.get(params["frameId"]) = Frame.new(params)
      end

      @session.on 'Page.frameDetached' do |params|
        @frames.delete(params['frameId'])
        puts "**** frameDetached called with #{params}" if ENV['DEBUG']
      end

      @session.on 'Page.frameNavigated' do |params|
        puts "**** frameNavigated called with #{params}" if ENV['DEBUG']
        frame_params = params['frame']
        unless @frames.exists?(frame_params['id'])
          puts "**** creating frome for #{frame_params['id']}" if ENV['DEBUG']
          @frames.add(frame_params['id'], frame_params)
        end

        # @frames.get(frame_params['id']).state = :loaded if frame_params['id'] == main_frame.id
        temp_headers.clear
        # puts "need to update headers without hanging???"
        # update_headers
      end

      @session.on 'Page.lifecycleEvent' do |params|
        puts "Lifecycle: #{params['name']} - frame: #{params['frameId']} - loader: #{params['loaderId']}" if ENV['DEBUG']
        case params['name']
        when 'init'
          frame = @frames.get(params['frameId'])
          frame.loader_id = params['loaderId'] if frame
        when 'firstMeaningfulPaintCandidate',
             'networkIdle'
          # @frames.get(params['frameId']).state = :loaded
          frame = @frames.get(params['frameId'])
          frame.loader_id = nil if frame.loader_id == params['loaderId']
        end
      end

      @session.on 'Page.navigatedWithinDocument' do |params|
        puts "**** navigatedWithinDocument called with #{params}" if ENV['DEBUG']
        frame_id = params['frameId']
        # @frames.get(frame_id).state = :loaded if frame_id == main_frame.id
        @frames.get(frame_id).loader_id = nil if frame_id == main_frame.id
      end

      # @session.on 'Page.frameStartedLoading' do |params|
      #   frame = @frames.get(params['frameId'])
      #   if frame
      #     @status_code = nil if frame.id == main_frame.id
      #     frame.state = :loading
      #   end
      # end

      # @session.on 'Page.frameStoppedLoading' do |params|
      #   frame = @frames.get(params['frameId'])
      #   frame.state = :loaded if frame
      # end

      @session.on 'Runtime.executionContextCreated' do |params|
        puts "**** executionContextCreated: #{params}" if ENV['DEBUG']
        context = params['context']
        frame_id = context.dig('auxData', 'frameId')
        if context.dig('auxData', 'isDefault') && frame_id
          if (frame = @frames.get(frame_id))
            frame.context_id = context['id']
          elsif ENV['DEBUG']
            puts "unknown frame for context #{frame_id}"
          end
        end
        # command 'Network.setRequestInterception', patterns: [{urlPattern: '*'}]
      end

      @session.on 'Runtime.executionContextDestroyed' do |params|
        puts "executionContextDestroyed: #{params}" if ENV['DEBUG']
        @frames.destroy_context(params['executionContextId'])
      end

      @session.on 'Network.requestWillBeSent' do |params|
        @network_traffic.push(NetworkTraffic::Request.new(params))
      end

      @session.on 'Network.responseReceived' do |params|
        req = @network_traffic.find { |request| request.request_id == params['requestId'] }
        req.response = NetworkTraffic::Response.new(params['response']) if req
      end

      @session.on 'Network.responseReceived' do |params|
        if params['type'] == 'Document'
          @response_headers = params['response']['headers']
          @status_code = params['response']['status']
        end
      end

      @session.on 'Network.loadingFailed' do |params|
        req = @network_traffic.find { |request| request.request_id == params['requestId'] }
        req&.blocked_params = params if params['blockedReason']
        puts "Loading Failed for request: #{params['requestId']}: #{params['errorText']}" if params['type'] == 'Document'
      end

      @session.on 'Network.requestIntercepted' do |params|
        request = params['request']
        interception_id = params['interceptionId']

        if params['authChallenge']
          credentials_response = if @auth_attempts.include?(interception_id)
            { response: 'CancelAuth' }
          else
            @auth_attempts.push(interception_id)
            { response: 'ProvideCredentials' }.merge(@credentials || {})
          end

          command('Network.continueInterceptedRequest',
                  interceptionId: interception_id,
                  authChallengeResponse: credentials_response)
        else
          url = request['url']
          if @url_blacklist.any? { |r| url.match Regexp.escape(r).gsub('\*', '.*?') }
            command('Network.continueInterceptedRequest', errorReason: 'Failed', interceptionId: interception_id)
          elsif @url_whitelist.any?
            if @url_whitelist.any? { |r| url.match Regexp.escape(r).gsub('\*', '.*?') }
              command('Network.continueInterceptedRequest', interceptionId: interception_id)
            else
              command('Network.continueInterceptedRequest', errorReason: 'Failed', interceptionId: interception_id)
            end
          else
            command('Network.continueInterceptedRequest', interceptionId: interception_id)
          end
        end
      end

      @session.on 'Runtime.consoleAPICalled' do |params|
        @browser.logger&.puts("#{params['type']}: #{params['args'].map { |arg| arg['description'] || arg['value'] }.join(' ')}")
      end
    end

    def setup_network_blocking
      command 'Network.setBlockedURLs', urls: @url_blacklist
      # if @url_whitelist.empty?
      #   command 'Network.setBlockedURLs', urls: @url_blacklist
      # else
      #   command 'Network.setBlockedURLs', urls: []
      # end
      setup_network_interception
    end

    def setup_network_interception
      # enabled, patterns = if @credentials || @url_whitelist.any? || @url_blacklist.any?
      #   puts 'setting interception'
      #   [true, [{ urlPattern: '*' }]]
      # else
      #   puts 'clearing interception'
      #   [false, []]
      # end
      # command 'Network.setCacheDisabled', cacheDisabled: enabled
      # command 'Network.setRequestInterception', patterns: patterns
      command 'Network.setCacheDisabled', cacheDisabled: true
      command 'Network.setRequestInterception', patterns: [{ urlPattern: '*' }]
    end

    def current_frame
      @frames.current
    end

    def main_frame
      @frames.main
    end

    def go_history(delta)
      history = command('Page.getNavigationHistory')
      entry = history['entries'][history['currentIndex'] + delta]
      return nil unless entry

      command('Page.navigateToHistoryEntry', entryId: entry['id'])
    end

    def _execute_script(script, *args)
      args = args.map do |arg|
        if arg.is_a? Capybara::Apparition::Node
          { objectId: arg.id }
        else
          { value: arg }
        end
      end
      context_id = current_frame&.context_id
      # start = Time.now
      # until context_id do
      #   byebug if Time.now - start > 10
      #   #
      #   # raise TimeoutError if Time.now - start > 10
      #   context_id = current_frame&.context_id
      # end
      response = command('Runtime.callFunctionOn',
                         functionDeclaration: script,
                         executionContextId: context_id,
                         arguments: args,
                         returnByValue: false,
                         awaitPromise: true)
      process_response(response)
    end

    def _raw_evaluate(page_function, context_id: nil)
      wait_for_loaded
      return unless page_function.is_a? String

      context_id ||= current_frame.context_id

      response = command('Runtime.evaluate',
                         expression: page_function,
                         contextId: context_id,
                         returnByValue: false,
                         awaitPromise: true)
      process_response(response)
    end

    def process_response(response)
      return nil if response.nil?

      exception_details = response['exceptionDetails']
      if (exception = exception_details&.dig('exception'))
        case exception['className']
        when 'DOMException'
          raise ::Capybara::Apparition::BrowserError.new('name' => exception['description'], 'args' => nil)
        when 'ObsoleteException'
          raise ::Capybara::Apparition::ObsoleteNode.new(self, '') if exception['value'] == 'ObsoleteNode'
        else
          raise Capybara::Apparition::JavascriptError, [exception['description']]
        end
      end

      result = response['result']
      decode_result(result)
    end

    def decode_result(result, object_cache = {})
      if result['type'] == 'object'
        if result['subtype'] == 'array'
          # remoteObject = @browser.command('Runtime.getProperties',
          remote_object = command('Runtime.getProperties',
                                  objectId: result['objectId'],
                                  ownProperties: true)

          properties = remote_object['result']
          results = []

          properties.each do |property|
            next unless property['enumerable']

            val = property['value']
            results.push(decode_result(val, object_cache))
            # await Promise.all(releasePromises);
            # id = (@page._elements.push(element)-1 for element from result)[0]
            #
            # new Apparition.Node @page, id

            # releasePromises = [helper.releaseObject(@element._client, remoteObject)]
          end

          return results
        elsif result['subtype'] == 'node'
          return result
        elsif result['className'] == 'Object'
          remote_object = command('Runtime.getProperties',
                                  objectId: result['objectId'],
                                  ownProperties: true)
          stable_id = remote_object["internalProperties"].find { |prop| prop["name"] == "[[StableObjectId]]" }.dig("value", "value")
          # We could actually return cyclic objects here but Capybara would need to be updated to support
          return '(cyclic structure)' if object_cache.key?(stable_id)
          # return object_cache[stable_id] if object_cache.key?(stable_id)

          object_cache[stable_id] = {}
          properties = remote_object['result']

          return properties.each_with_object(object_cache[stable_id]) do |property, memo|
            if property['enumerable']
              memo[property['name']] = decode_result(property['value'], object_cache)
            else
              #     releasePromises.push(helper.releaseObject(@element._client, property.value))
            end
            # releasePromises = [helper.releaseObject(@element._client, remote_object)]
          end
        elsif result['className'] == 'Window'
          return { object_id: result['objectId'] }
        end
        nil
      else
        result['value']
      end
    end
  end
end
