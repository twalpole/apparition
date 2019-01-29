# frozen_string_literal: true

require 'capybara/apparition/page/frame_manager'
require 'capybara/apparition/page/mouse'
require 'capybara/apparition/page/keyboard'

module Capybara::Apparition
  class Page
    attr_reader :modal_messages
    attr_reader :mouse, :keyboard
    attr_reader :viewport_size
    attr_accessor :perm_headers, :temp_headers, :temp_no_redirect_headers
    attr_reader :network_traffic

    def self.create(browser, session, id, ignore_https_errors: false, screenshot_task_queue: nil, js_errors: false)
      session.command 'Page.enable'

      # Provides a lot of info - but huge overhead
      # session.command 'Page.setLifecycleEventsEnabled', enabled: true

      page = Page.new(browser, session, id, ignore_https_errors, screenshot_task_queue, js_errors)

      session.async_commands 'Network.enable', 'Runtime.enable', 'Security.enable', 'DOM.enable'
      # session.command 'Network.enable'
      # session.command 'Runtime.enable'
      # session.command 'Security.enable'
      # session.command 'Security.setOverrideCertificateErrors', override: true if ignore_https_errors
      session.command 'Security.setIgnoreCertificateErrors', ignore: !!ignore_https_errors
      # session.command 'DOM.enable'
      # session.command 'Log.enable'
      if Capybara.save_path
        session.command 'Page.setDownloadBehavior', behavior: 'allow', downloadPath: Capybara.save_path
      end
      page
    end

    def initialize(browser, session, id, _ignore_https_errors, _screenshot_task_queue, js_errors)
      @target_id = id
      @browser = browser
      @session = session
      @keyboard = Keyboard.new(self)
      @mouse = Mouse.new(self, @keyboard)
      @modals = []
      @modal_messages = []
      @frames = Capybara::Apparition::FrameManager.new(id)
      @response_headers = {}
      @status_code = 0
      @url_blacklist = []
      @url_whitelist = []
      @auth_attempts = []
      @perm_headers = {}
      @temp_headers = {}
      @temp_no_redirect_headers = {}
      @viewport_size = nil
      @network_traffic = []
      @open_resource_requests = {}
      @raise_js_errors = js_errors
      @js_error = nil
      @modal_mutex = Mutex.new
      @modal_closed = ConditionVariable.new

      register_event_handlers

      register_js_error_handler # if js_errors
    end

    def usable?
      !!current_frame&.context_id
    end

    def reset
      @modals.clear
      @modal_messages.clear
      @response_headers = {}
      @status_code = 0
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
      frame_offset(current_frame)
    end

    def render(options)
      wait_for_loaded
      if options[:format].to_s == 'pdf'
        params = {}
        params[:paperWidth] = @browser.paper_size[:width].to_f if @browser.paper_size
        params[:paperHeight] = @browser.paper_size[:height].to_f if @browser.paper_size
        params[:scale] = @browser.zoom_factor if @browser.zoom_factor
        command('Page.printToPDF', params)
      else
        clip_options = if options[:selector]
          pos = evaluate("document.querySelector('#{options.delete(:selector)}').getBoundingClientRect().toJSON();")
          %w[x y width height].each_with_object({}) { |key, hash| hash[key] = pos[key] }
        elsif options[:full]
          evaluate <<~JS
            { width: document.documentElement.clientWidth, height: document.documentElement.clientHeight}
          JS
        else
          evaluate <<~JS
            { width: window.innerWidth, height: window.innerHeight }
          JS
        end
        options[:clip] = { x: 0, y: 0, scale: 1 }.merge(clip_options)
        options[:clip][:scale] = @browser.zoom_factor || 1
        command('Page.captureScreenshot', options)
      end['data']
    end

    def push_frame(frame_el)
      node = command('DOM.describeNode', objectId: frame_el.base.id)
      frame_id = node['node']['frameId']

      timer = Capybara::Helpers.timer(expire_in: 10)
      while (frame = @frames.get(frame_id)).nil? || frame.loading?
        # Wait for the frame creation messages to be processed
        if timer.expired?
          puts 'Timed out waiting from frame to be ready'
          # byebug
          raise TimeoutError.new('push_frame')
        end
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
      query = method == :css ? CSS_FIND_JS : XPATH_FIND_JS
      result = _raw_evaluate(query % js_escaped_selector)
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
      main_frame.reloading!
      command('Page.reload', ignoreCache: true)
      wait_for_loaded
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
      timer = Capybara::Helpers.timer(expire_in: 10)
      cf = current_frame
      until cf.usable? || (allow_obsolete && cf.obsolete?) || @js_error
        if timer.expired?
          puts 'Timedout waiting for page to be loaded'
          raise TimeoutError.new('wait_for_loaded')
        end
        sleep 0.05
      end
      raise JavascriptError.new(js_error) if @js_error
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
      @status_code = 0
      navigate_opts = { url: url, transitionType: 'reload' }
      navigate_opts[:referrer] = extra_headers['Referer'] if extra_headers['Referer']
      response = command('Page.navigate', navigate_opts)

      raise StatusFailError, 'args' => [url, response['errorText']] if response['errorText']

      main_frame.loading(response['loaderId'])
      wait_for_loaded
    rescue TimeoutError
      raise StatusFailError.new('args' => [url])
    end

    def current_url
      wait_for_loaded
      _raw_evaluate('window.location.href', context_id: main_frame.context_id)
    end

    def element_from_point(x:, y:)
      r_o = _raw_evaluate("document.elementFromPoint(#{x}, #{y})", context_id: main_frame.context_id)
      while r_o && (r_o['description'] =~ /^iframe/)
        frame_node = command('DOM.describeNode', objectId: r_o['objectId'])
        frame = @frames.get(frame_node.dig('node', 'frameId'))
        fo = frame_offset(frame)
        r_o = _raw_evaluate("document.elementFromPoint(#{x - fo[:x]}, #{y - fo[:y]})", context_id: frame.context_id)
      end
      r_o
    end

    def frame_url
      wait_for_loaded
      _raw_evaluate('window.location.href')
    end

    def set_viewport(width:, height:, screen: nil)
      wait_for_loaded
      @viewport_size = { width: width, height: height }
      result = @browser.command('Browser.getWindowForTarget', targetId: @target_id)
      @browser.command('Browser.setWindowBounds',
                       windowId: result['windowId'],
                       bounds: { width: width, height: height })
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

    def command(name, **params)
      @browser.command_for_session(@session.session_id, name, params).result
    end

    def async_command(name, **params)
      @browser.command_for_session(@session.session_id, name, params).discard_result
    end

    def extra_headers
      temp_headers.merge(perm_headers).merge(temp_no_redirect_headers)
    end

    def update_headers(async: false)
      method = async ? :async_command : :command
      if (ua = extra_headers.find { |k, _v| k =~ /^User-Agent$/i })
        send(method, 'Network.setUserAgentOverride', userAgent: ua[1])
      end
      send(method, 'Network.setExtraHTTPHeaders', headers: extra_headers)
      setup_network_interception
    end

    def inherit(page)
      if page
        self.url_whitelist = page.url_whitelist.dup
        self.url_blacklist = page.url_blacklist.dup
        set_viewport(page.viewport_size) if page.viewport_size
      end
      self
    end

    def js_error
      res = @js_error
      @js_error = nil
      res
    end

  protected

    attr_reader :url_blacklist, :url_whitelist

  private

    def frame_offset(frame)
      return { x: 0, y: 0 } if frame.id == main_frame.id

      result = command('DOM.getBoxModel', objectId: frame.element_id)
      x, y = result['model']['content']
      { x: x, y: y }
    end

    def register_event_handlers
      @session.on 'Page.javascriptDialogOpening' do |params|
        type = params['type'].to_sym
        accept = accept_modal?(type, params['message'])
        next if accept.nil?

        if type == :prompt
          case accept
          when false
            async_command('Page.handleJavaScriptDialog', accept: false)
          when true
            async_command('Page.handleJavaScriptDialog', accept: true, promptText: params['defaultPrompt'])
          else
            async_command('Page.handleJavaScriptDialog', accept: true, promptText: accept)
          end
        else
          async_command('Page.handleJavaScriptDialog', accept: accept)
        end
      end

      @session.on 'Page.javascriptDialogClosed' do
        @modal_mutex.synchronize do
          @modal_closed.signal
        end
      end

      @session.on 'Page.windowOpen' do |params|
        puts "**** windowOpen was called with: #{params}" if ENV['DEBUG']
        # TODO: find a better way to handle this
        sleep 0.4 # wait a bit so the window has time to start loading
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
      end

      @session.on 'Page.frameStartedLoading' do |params|
        @frames.get(params['frameId'])&.loading(-1)
      end

      @session.on 'Page.frameStoppedLoading' do |params|
        @frames.get(params['frameId'])&.loaded!
      end

      # @session.on 'Page.lifecycleEvent' do |params|
      #   # Provides a lot of useful info - but lots of overhead
      #   puts "Lifecycle: #{params['name']} - frame: #{params['frameId']} - loader: #{params['loaderId']}" if ENV['DEBUG']
      #   case params['name']
      #   when 'init'
      #     @frames.get(params['frameId'])&.loading(params['loaderId'])
      #   when 'firstMeaningfulPaint',
      #        'networkIdle'
      #     @frames.get(params['frameId']).tap do |frame|
      #       frame.loaded! if frame.loader_id == params['loaderId']
      #     end
      #   end
      # end

      @session.on('Page.domContentEventFired') do
        # TODO: Really need something better than this
        main_frame.loaded! if @status_code != 200
      end

      @session.on 'Page.navigatedWithinDocument' do |params|
        puts "**** navigatedWithinDocument called with #{params}" if ENV['DEBUG']
        frame_id = params['frameId']
        # @frames.get(frame_id).state = :loaded if frame_id == main_frame.id
        @frames.get(frame_id).loaded! if frame_id == main_frame.id
      end

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
        @open_resource_requests[params['requestId']] = params.dig('request', 'url')
      end

      @session.on 'Network.responseReceived' do |params|
        @open_resource_requests.delete(params['requestId'])
        temp_headers.clear
        update_headers(async: true)
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
        if params['type'] == 'Document'
          puts "Loading Failed - request: #{params['requestId']} : #{params['errorText']}" if ENV['DEBUG']
        end
      end

      @session.on 'Network.requestIntercepted' do |params|
        request, interception_id = *params.values_at('request', 'interceptionId')
        if params['authChallenge']
          handle_auth(interception_id)
        else
          process_intercepted_request(interception_id, request, params['isNavigationRequest'])
        end
      end

      @session.on 'Runtime.consoleAPICalled' do |params|
        # {"type"=>"log", "args"=>[{"type"=>"string", "value"=>"hello"}], "executionContextId"=>2, "timestamp"=>1548722854903.285, "stackTrace"=>{"callFrames"=>[{"functionName"=>"", "scriptId"=>"15", "url"=>"http://127.0.0.1:53977/", "lineNumber"=>6, "columnNumber"=>22}]}}
        details = params.dig('stackTrace', 'callFrames')&.first
        @browser.console.log(params['type'],
                             params['args'].map { |arg| arg['description'] || arg['value'] }.join(' ').to_s,
                             source: details['url'].empty? ? nil : details['url'],
                             line_number: details['lineNumber'].zero? ? nil : details['lineNumber'],
                             columnNumber: details['columnNumber'].zero? ? nil : details['columnNumber'])
      end

      # @session.on 'Security.certificateError' do |params|
      #   async_command 'Network.continueInterceptedRequest', interceptionId: id, **params
      # end

      # @session.on 'Log.entryAdded' do |params|
      #   log_entry = params['entry']
      #   if params.values_at('source', 'level') == ['javascript', 'error']
      #     @js_error ||= params['string']
      #   end
      # end
    end

    def register_js_error_handler
      @session.on 'Runtime.exceptionThrown' do |params|
        @js_error ||= params.dig('exceptionDetails', 'exception', 'description') if @raise_js_errors

        details = params.dig('exceptionDetails', 'stackTrace', 'callFrames')&.first
        @browser.console.log('error',
                             params.dig('exceptionDetails', 'exception', 'description'),
                             source: details['url'].empty? ? nil : details['url'],
                             line_number: details['lineNumber'].zero? ? nil : details['lineNumber'],
                             columnNumber: details['columnNumber'].zero? ? nil : details['columnNumber'])
      end
    end

    def setup_network_blocking
      command 'Network.setBlockedURLs', urls: @url_blacklist
      setup_network_interception
    end

    def setup_network_interception
      async_command 'Network.setCacheDisabled', cacheDisabled: true
      async_command 'Network.setRequestInterception', patterns: [{ urlPattern: '*' }]
    end

    def process_intercepted_request(interception_id, request, navigation)
      headers, url = request.values_at('headers', 'url')

      unless @temp_headers.empty? || navigation # rubocop:disable Style/IfUnlessModifier
        headers.delete_if { |name, value| @temp_headers[name] == value }
      end
      unless @temp_no_redirect_headers.empty? || !navigation
        headers.delete_if { |name, value| @temp_no_redirect_headers[name] == value }
      end

      if @url_blacklist.any? { |r| url.match Regexp.escape(r).gsub('\*', '.*?') }
        block_request(interception_id, 'Failed')
      elsif @url_whitelist.any?
        if @url_whitelist.any? { |r| url.match Regexp.escape(r).gsub('\*', '.*?') }
          continue_request(interception_id, headers: headers)
        else
          block_request(interception_id, 'Failed')
        end
      else
        continue_request(interception_id, headers: headers)
      end
    end

    def continue_request(id, **params)
      async_command 'Network.continueInterceptedRequest', interceptionId: id, **params
    end

    def block_request(id, reason)
      async_command 'Network.continueInterceptedRequest', errorReason: reason, interceptionId: id
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

      main_frame.loading(-1)
      command('Page.navigateToHistoryEntry', entryId: entry['id'])
      wait_for_loaded
    end

    def accept_modal?(type, message)
      if type == :beforeunload
        true
      else
        response = @modals.pop
        if !response&.key?(type)
          if params['hasBrowserHandler']
            manual_unexpected_modal(type)
          else
            auto_unexpected_modal(type)
          end
        else
          @modal_messages.push(message)
          response[type].nil? ? true : response[type]
        end
      end
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

    def manual_unexpected_modal(type)
      warn "An unexpected #{type} modal has opened - please close"
      @modal_mutex.synchronize do
        @modal_closed.wait(@modal_mutex)
      end
      nil
    end

    def auto_unexpected_modal(type)
      case type
      when :prompt
        warn 'Unexpected prompt modal - accepting with the default value.' \
             'You should be using `accept_prompt` or `dismiss_prompt`.'
      when :confirm
        warn 'Unexpected confirm modal - accepting.' \
             'You should be using `accept_confirm` or `dismiss_confirm`.'
      else
        warn 'Unexpected alert modal - clearing.' \
             'You should be using `accept_alert`.'
      end
      true
    end

    def handle_auth(interception_id)
      credentials_response = if @auth_attempts.include?(interception_id)
        { response: 'CancelAuth' }
      else
        @auth_attempts.push(interception_id)
        { response: 'ProvideCredentials' }.merge(@credentials || {})
      end
      continue_request(interception_id, authChallengeResponse: credentials_response)
    end

    def decode_result(result, object_cache = {})
      if result['type'] == 'object'
        if result['subtype'] == 'array'
          remote_object = command('Runtime.getProperties',
                                  objectId: result['objectId'],
                                  ownProperties: true)

          properties = remote_object['result']
          results = []

          properties.each do |property|
            next unless property['enumerable']

            val = property['value']
            results.push(decode_result(val, object_cache))
            # TODO: Do we need to cleanup these resources?
            # await Promise.all(releasePromises);
            # id = (@page._elements.push(element)-1 for element from result)[0]
            #
            # new Apparition.Node @page, id

            # releasePromises = [helper.releaseObject(@element._client, remoteObject)]
          end
          command('Runtime.releaseObject', objectId: result['objectId'])
          return results
        elsif result['subtype'] == 'node'
          return result
        elsif result['className'] == 'Object'
          remote_object = command('Runtime.getProperties',
                                  objectId: result['objectId'],
                                  ownProperties: true)
          stable_id = remote_object['internalProperties']
                      .find { |prop| prop['name'] == '[[StableObjectId]]' }
                      .dig('value', 'value')
          # We could actually return cyclic objects here but Capybara would need to be updated to support
          # return object_cache[stable_id] if object_cache.key?(stable_id)

          return '(cyclic structure)' if object_cache.key?(stable_id)

          object_cache[stable_id] = {}
          properties = remote_object['result']

          return properties.each_with_object(object_cache[stable_id]) do |property, memo|
            if property['enumerable']
              memo[property['name']] = decode_result(property['value'], object_cache)
            else # rubocop:disable Style/EmptyElse
              # TODO: Do we need to cleanup these resources?
              #     releasePromises.push(helper.releaseObject(@element._client, property.value))
            end
            # TODO: Do we need to cleanup these resources?
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

    CSS_FIND_JS = <<~JS
      Array.from(document.querySelectorAll("%s"));
    JS

    XPATH_FIND_JS = <<~JS
      (function(){
        const xpath = document.evaluate("%s", document, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
        let results = [];
        for (let i=0; i < xpath.snapshotLength; i++){
          results.push(xpath.snapshotItem(i))
        };
        return results;
      })()
    JS
  end
end
