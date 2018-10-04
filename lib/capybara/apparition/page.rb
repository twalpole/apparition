# frozen_string_literal: true

require 'capybara/apparition/frame'
require 'capybara/apparition/mouse'
require 'capybara/apparition/keyboard'

module Capybara::Apparition
  class Page
    attr_reader :modal_messages
    attr_reader :mouse, :keyboard

    def self.create(browser, session, id, ignoreHTTPSErrors, screenshotTaskQueue)
      session.command 'Page.enable'

      page = Page.new(browser, session, id, ignoreHTTPSErrors, screenshotTaskQueue)
      session.command 'Network.enable'
      session.command 'Runtime.enable'
      sleep 1
      session.command 'Security.enable'

      session.command 'Security.setOverrideCertificateErrors', override: true if ignoreHTTPSErrors

      session.command 'DOM.enable'

      # Initialize default page size.
      page.set_viewport width: 800, height: 600

      # page.visit 'about:blank'
      page
    end

    def initialize(browser, session, id, _ignoreHTTPSErrors, _screenshotTaskQueue)
      @browser = browser
      @session = session
      @keyboard = Keyboard.new(self)
      @mouse = Mouse.new(self, @keyboard)
      @modals = []
      @modal_messages = []
      @frames = {}
      @frames[id] = Frame.new(self, frameId: id)
      @current_frame = @main_frame = @frames[id]
      @response_headers = {}
      @status_code = nil
      @url_blacklist = []
      @url_whitelist = []
      @auth_attempts = []
      @current_loader_id = nil

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
        # @frames[params["frameId"]] = Frame.new(params)
      end

      @session.on 'Page.frameDetached' do |params|
        @frames.delete(params['frameId'])
        puts "**** frameDetached called with #{params}" if ENV['DEBUG']
      end

      @session.on 'Page.frameNavigated' do |params|
        puts "**** frameNavigated called with #{params}" if ENV['DEBUG']
        frame_params = params['frame']
        unless @frames.key?(frame_params['id'])
          puts "**** creating frome for #{frame_params['id']}" if ENV['DEBUG']
          @frames[frame_params['id']] = Frame.new(self, frame_params)
        end

        @frames[frame_params['id']].state = :loaded if frame_params['id'] == @main_frame.id
      end

      @session.on 'Page.frameStartedLoading' do |params|
        frame = @frames[params['frameId']]
        frame.state = :loading if frame
      end

      @session.on 'Page.frameStoppedLoading' do |params|
        frame = @frames[params['frameId']]
        frame.state = :loaded if frame
      end

      @session.on 'Runtime.executionContextCreated' do |params|
        puts "**** executionContextCreated: #{params}" if ENV['DEBUG']
        context = params['context']
        frameId = context.dig('auxData', 'frameId')
        if context.dig('auxData', 'isDefault') && frameId
          if @frames.key?(frameId)
            @frames[frameId].context_id = context['id']
          else
            puts "unknown frame for context #{frameId}" if ENV['DEBUG']
          end
        end
        # command 'Network.setRequestInterception', patterns: [{urlPattern: '*'}]
      end

      @session.on 'Runtime.executionContextDestroyed' do |params|
        puts "executionContextDestroyed: #{params}" if ENV['DEBUG']
        @frames.select do |_id, f|
          f.context_id == params['executionContextId']
        end.each { |_id, f| f.context_id = nil }
      end

      @session.on 'Network.responseReceived' do |params|
        if params['type'] == 'Document'
          @response_headers = params['response']['headers']
          @status_code = params['response']['status']
        end
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

      @session.on 'Network.loadingFinished' do |params|
      end

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

    def reset
      @modals.clear
      @modal_messages.clear
      @response_headers = {}
      @status_code = nil
      @auth_attempts = []
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

    def scroll_to(left, top)
      execute('window.scrollTo(arguments[0], arguments[1])', left, top)
    end

    def click_at(x, y)
      @mouse.click_at(x: x, y: y)
    end

    def current_state
      @main_frame.state
    end

    def current_frame_offset
      return { x: 0, y: 0 } if current_frame == @main_frame

      result = command('DOM.getBoxModel', objectId: current_frame.element_id)
      x, y = result['model']['content']
      { x: x, y: y }
    end

    def render(options)
      res = command('Page.captureScreenshot', options)
      res['data']
    end

    def push_frame(frame_el)
      node = command('DOM.describeNode', objectId: frame_el.base.id)
      frame_id = node['node']['frameId']
      while (frame = @frames[frame_id]).nil? || frame.loading?
        # Wait for the frame creation messages to be processed
        sleep 0.1
      end
      return unless frame

      frame.element_id = frame_el.base.id
      @current_frame = frame
    end

    def pop_frame(top: false)
      @current_frame = if top
        @main_frame
      else
        @current_frame = @frames[@current_frame.parent_id]
      end
    end

    def find(method, selector)
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
      result.map { |r_o| [self, r_o['objectId']] }
    rescue ::Capybara::Apparition::BrowserError => e
      raise unless e.name =~ /is not a valid (XPath expression|selector)/

      raise Capybara::Apparition::InvalidSelector, [method, selector]
    end

    def execute(script, *args)
      _execute_script("function(){ #{script} }", *args)
      nil
    end

    def evaluate(script, *args)
      _execute_script("function(){ return #{script} }", *args)
    end

    def evaluate_async(script, _wait_time, *args)
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
      command('Page.reload')
    end

    def go_back
      go_history(-1)
    end

    def go_forward
      go_history(+1)
    end

    attr_reader :response_headers

    attr_reader :status_code

    def content
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
      @main_frame.state = :loading
      response = command('Page.navigate', url: url)
      @current_loader_id = response['loaderId']
      sleep 0.05 while current_state == :loading
    end

    def current_url
      _raw_evaluate('window.location.href')
    end

    def set_viewport(width:, height:)
      command('Emulation.setDeviceMetricsOverride', mobile: false, width: width, height: height, deviceScaleFactor: 1, screenOrientation: { angle: 0, type: 'portraitPrimary' })
    end

    def title
      _raw_evaluate('document.title')
    end

    def command(name, params = {})
      @browser.command_for_session(@session.session_id, name, params)
    end

  private

    def setup_network_blocking
      # if @url_whitelist.empty?
      #   command 'Network.setBlockedURLs', urls: @url_blacklist
      # else
      #   command 'Network.setBlockedURLs', urls: []
      # end
      setup_network_interception
    end

    def setup_network_interception
      enabled, patterns = if @credentials || @url_whitelist.any? || @url_blacklist.any?
        puts 'setting interception'
        [true, [{ urlPattern: '*' }]]
      else
        puts 'clearing interception'
        [false, []]
      end
      command 'Network.setCacheDisabled', cacheDisabled: enabled
      command 'Network.setRequestInterception', patterns: patterns
    end

    attr_reader :current_frame

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
      response = command('Runtime.callFunctionOn',
                         functionDeclaration: script,
                         executionContextId: current_frame.context_id,
                         arguments: args,
                         returnByValue: false,
                         awaitPromise: true)
      process_response(response)
    end

    def _raw_evaluate(page_function)
      return unless page_function.is_a? String

      response = command('Runtime.evaluate',
                         expression: page_function,
                         contextId: current_frame.context_id,
                         returnByValue: false,
                         awaitPromise: true)
      process_response(response)
    end

    def process_response(response)
      exception_details = response['exceptionDetails']
      if (exception = exception_details&.dig('exception'))
        case exception['className']
        when 'DOMException'
          raise ::Capybara::Apparition::BrowserError.new('name' => exception['description'], 'args' => nil)
        else
          raise ::Capybara::Apparition::ObsoleteNode.new(self, '') if exception['value'] == 'ObsoleteNode'

          puts "Unknown Exception: #{exception['value']}"
        end
        raise exception_details
      end

      result = response['result']
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
            if val['subtype'] == 'node'
              #     result.push(new ElementHandle(@element._frame, @element._client, property.value, @element._mouse))
              results.push(val)
            else
              #     releasePromises.push(helper.releaseObject(@element._client, property.value))
              results.push(val['value'])
            end
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
          properties = remote_object['result']

          return properties.each_with_object({}) do |property, memo|
            if property['enumerable']
              memo[property['name']] = property['value']['value']
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
