# frozen_string_literal: true

require 'capybara/apparition/dev_tools_protocol/remote_object'
require 'capybara/apparition/page/frame_manager'
require 'capybara/apparition/page/mouse'
require 'capybara/apparition/page/keyboard'

module Capybara::Apparition
  class Page
    attr_reader :modal_messages
    attr_reader :mouse, :keyboard
    attr_reader :viewport_size
    attr_reader :browser_context_id
    attr_accessor :perm_headers, :temp_headers, :temp_no_redirect_headers
    attr_reader :network_traffic
    attr_reader :target_id

    def self.create(browser, session, id, browser_context_id,
                    ignore_https_errors: false, **options)
      session.async_command 'Page.enable'

      # Provides a lot of info - but huge overhead
      # session.command 'Page.setLifecycleEventsEnabled', enabled: true

      page = Page.new(browser, session, id, browser_context_id, **options)

      session.async_commands 'Network.enable', 'Runtime.enable', 'Security.enable', 'DOM.enable'
      session.async_command 'Security.setIgnoreCertificateErrors', ignore: !!ignore_https_errors
      if Capybara.save_path
        session.async_command 'Page.setDownloadBehavior', behavior: 'allow', downloadPath: Capybara.save_path
      end
      page
    end

    def initialize(browser, session, target_id, browser_context_id,
                   js_errors: false, url_blacklist: [], url_whitelist: [], extensions: [])
      @target_id = target_id
      @browser_context_id = browser_context_id
      @browser = browser
      @session = session
      @keyboard = Keyboard.new(self)
      @mouse = Mouse.new(self, @keyboard)
      @modals = []
      @modal_messages = []
      @frames = Capybara::Apparition::FrameManager.new(@target_id)
      @response_headers = {}
      @status_code = 0
      @url_blacklist = url_blacklist || []
      @url_whitelist = url_whitelist || []
      @credentials = nil
      @auth_attempts = []
      @proxy_credentials = nil
      @proxy_auth_attempts = []
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

      extensions.each do |name|
        add_extension(name)
      end

      setup_network_interception if browser.proxy_auth
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
      @proxy_auth_attempts = []
      @perm_headers = {}
    end

    def add_extension(filename)
      command('Page.addScriptToEvaluateOnNewDocument', source: File.read(filename))
    rescue Errno::ENOENT
      raise ::Capybara::Apparition::BrowserError.new('name' => "Unable to load extension: #{filename}", 'args' => nil)
    end

    def add_modal(modal_response)
      @last_modal_message = nil
      @modals.push(modal_response)
    end

    def proxy_credentials=(creds)
      @proxy_credentials = creds
      setup_network_interception
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
      pixel_ratio = evaluate('window.devicePixelRatio')
      scale = (@browser.zoom_factor || 1).to_f / pixel_ratio
      if options[:format].to_s == 'pdf'
        params = { scale: scale }
        if @browser.paper_size
          params[:paperWidth] = @browser.paper_size[:width].to_f
          params[:paperHeight] = @browser.paper_size[:height].to_f
        end
        command('Page.printToPDF', **params)
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
        options[:clip] = { x: 0, y: 0, scale: scale }.merge(clip_options)
        command('Page.captureScreenshot', **options)
      end['data']
    end

    def push_frame(frame_el)
      node = command('DOM.describeNode', objectId: frame_el.base.id)
      frame_id = node['node']['frameId']

      timer = Capybara::Helpers.timer(expire_in: 10)
      while (frame = @frames[frame_id]).nil? || frame.loading?
        # Wait for the frame creation messages to be processed
        if timer.expired?
          puts 'Timed out waiting for frame to be ready'
          raise TimeoutError.new('push_frame')
        end
        sleep 0.1
      end

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
      result = _raw_evaluate(format(query, selector: js_escaped_selector))
      (result || []).map { |r_o| [self, r_o['objectId'], tag_name: r_o['description'].split(/[.#]/, 2)[0]] }
    rescue ::Capybara::Apparition::BrowserError => e
      raise unless /is not a valid (XPath expression|selector)/.match? e.name

      raise Capybara::Apparition::InvalidSelector, 'args' => [method, selector]
    end

    def execute(script, *args)
      eval_wrapped_script(EXECUTE_JS, script, args)
      nil
    end

    def evaluate(script, *args)
      eval_wrapped_script(EVALUATE_WITH_ID_JS, script, args)
    end

    def evaluate_async(script, _wait_time, *args)
      eval_wrapped_script(EVALUATE_ASYNC_JS, script, args)
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

    def response_headers
      @response_headers[current_frame.id] || {}
    end

    attr_reader :status_code

    def wait_for_loaded(allow_obsolete: false)
      # We can't reliably detect if the page is loaded, so just ensure the context
      # is usable
      timer = Capybara::Helpers.timer(expire_in: 30)
      page_function = '(function(){ return 1 == 1; })()'
      begin
        response = command('Runtime.evaluate',
                           expression: page_function,
                           contextId: current_frame.context_id,
                           returnByValue: false,
                           awaitPromise: true)
        process_response(response)
        current_frame.loaded!
      rescue # rubocop:disable Style/RescueStandardError
        return if allow_obsolete && current_frame.obsolete?

        unless timer.expired?
          sleep 0.05
          retry
        end
        puts 'Timedout waiting for page to be loaded' if ENV['DEBUG']
        raise TimeoutError.new('wait_for_loaded')
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
      response = command('Page.navigate', **navigate_opts)
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
      while r_o&.[]('description')&.start_with?('iframe')
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
      # wait_for_loaded
      @viewport_size = { width: width, height: height }
      result = @browser.command('Browser.getWindowForTarget', targetId: @target_id)
      begin
        @browser.command('Browser.setWindowBounds',
                         windowId: result['windowId'],
                         bounds: { width: width, height: height })
      rescue WrongWorld # TODO: Fix Error naming here
        @browser.command('Browser.setWindowBounds', windowId: result['windowId'], bounds: { windowState: 'normal' })
        retry
      end

      metrics = {
        mobile: false,
        width: width,
        height: height,
        deviceScaleFactor: 1
      }
      metrics[:screenWidth], metrics[:screenHeight] = *screen if screen

      command('Emulation.setDeviceMetricsOverride', **metrics)
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
      if (ua = extra_headers.find { |k, _v| /^User-Agent$/i.match? k })
        send(async ? :async_command : :command, 'Network.setUserAgentOverride', userAgent: ua[1])
      end
      setup_network_interception
    end

    def inherit(page)
      if page
        self.url_whitelist = page.url_whitelist.dup
        self.url_blacklist = page.url_blacklist.dup
        set_viewport(**page.viewport_size) if page.viewport_size
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

    def current_frame
      @frames.current
    end

    def main_frame
      @frames.main
    end

  private

    def eval_wrapped_script(wrapper, script, args)
      wait_for_loaded
      _execute_script format(wrapper, script: script), *args
    end

    def frame_offset(frame)
      return { x: 0, y: 0 } if frame.id == main_frame.id

      result = command('DOM.getBoxModel', objectId: frame.element_id)
      x, y = result['model']['content']
      { x: x, y: y }
    end

    def register_event_handlers
      @session.on 'Page.javascriptDialogOpening' do |type:, message:, has_browser_handler:, **params|
        type = type.to_sym
        accept = accept_modal?(type, message: message, manual: has_browser_handler)
        next if accept.nil?

        if type == :prompt
          case accept
          when false
            async_command('Page.handleJavaScriptDialog', accept: false)
          when true
            async_command('Page.handleJavaScriptDialog', accept: true, promptText: params[:default_prompt])
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

      @session.on 'Page.windowOpen' do |**params|
        puts "**** windowOpen was called with: #{params}" if ENV['DEBUG']
        @browser.refresh_pages(opener: self)
      end

      @session.on 'Page.frameAttached' do |**params|
        puts "**** frameAttached called with #{params}" if ENV['DEBUG']
        # @frames.get(params["frameId"]) = Frame.new(params)
      end

      @session.on 'Page.frameDetached' do |frame_id:, **params|
        @frames.delete(frame_id)
        puts "**** frameDetached called with #{frame_id} : #{params}" if ENV['DEBUG']
      end

      @session.on 'Page.frameNavigated' do |frame:|
        puts "**** frameNavigated called with #{frame}" if ENV['DEBUG']
        unless @frames.exists?(frame['id'])
          puts "**** creating frame for #{frame['id']}" if ENV['DEBUG']
          @frames.add(frame['id'], frame)
        end
        @frames.get(frame['id'])&.loading(frame['loaderId'] || -1)
      end

      @session.on 'Page.frameStartedLoading' do |frame_id:|
        puts "Setting loading for #{frame_id}" if ENV['DEBUG']
        @frames.get(frame_id)&.loading(-1)
      end

      @session.on 'Page.frameStoppedLoading' do |frame_id:|
        puts "Setting loaded for #{frame_id}" if ENV['DEBUG']
        @frames.get(frame_id)&.loaded!
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

      @session.on 'Page.navigatedWithinDocument' do |frame_id:, **params|
        puts "**** navigatedWithinDocument called with #{frame_id}: #{params}" if ENV['DEBUG']
        @frames.get(frame_id).loaded! if frame_id == main_frame.id
      end

      @session.on 'Runtime.executionContextCreated' do |context:|
        frame_id = context.dig('auxData', 'frameId')
        if context.dig('auxData', 'isDefault') && frame_id
          if (frame = @frames.get(frame_id))
            frame.context_id = context['id']
          elsif ENV['DEBUG']
            puts "unknown frame for context #{frame_id}"
          end
        end
      end

      @session.on 'Runtime.executionContextDestroyed' do |execution_context_id:, **params|
        puts "executionContextDestroyed: #{execution_context_id} : #{params}" if ENV['DEBUG']
        @frames.destroy_context(execution_context_id)
      end

      @session.on 'Network.requestWillBeSent' do |request_id:, request: nil, **|
        @open_resource_requests[request_id] = request&.dig('url')
      end

      @session.on 'Network.responseReceived' do |request_id:, **|
        @open_resource_requests.delete(request_id)
        temp_headers.clear
        update_headers(async: true)
      end

      @session.on 'Network.requestWillBeSent' do |**params|
        @network_traffic.push(NetworkTraffic::Request.new(params))
      end

      @session.on 'Network.responseReceived' do |request_id:, response:, **|
        req = @network_traffic.find { |request| request.request_id == request_id }
        req.response = NetworkTraffic::Response.new(response) if req
      end

      @session.on 'Network.responseReceived' do |type:, frame_id: nil, response: nil, **|
        if type == 'Document'
          @response_headers[frame_id] = response['headers']
          @status_code = response['status']
        end
      end

      @session.on 'Network.loadingFailed' do |type:, request_id:, blocked_reason: nil, error_text: nil, **params|
        req = @network_traffic.find { |request| request.request_id == request_id }
        req&.blocked_params = params if blocked_reason
        if type == 'Document'
          puts "Loading Failed - request: #{request_id} : #{error_text}" if ENV['DEBUG']
        end
      end

      @session.on 'Fetch.requestPaused' do |request:, request_id:, resource_type:, **|
        process_intercepted_fetch(request_id, request, resource_type)
      end

      @session.on 'Fetch.authRequired' do |request_id:, auth_challenge: nil, **|
        next unless auth_challenge

        credentials_response = if auth_challenge['source'] == 'Proxy'
          if @proxy_auth_attempts.include?(request_id)
            puts 'Cancelling proxy auth' if ENV['DEBUG']
            { response: 'CancelAuth' }
          else
            puts 'Replying with proxy auth credentials' if ENV['DEBUG']
            @proxy_auth_attempts.push(request_id)
            { response: 'ProvideCredentials' }.merge(@browser.proxy_auth || {})
          end
        elsif @auth_attempts.include?(request_id)
          puts 'Cancelling auth' if ENV['DEBUG']
          { response: 'CancelAuth' }
        else
          @auth_attempts.push(request_id)
          puts 'Replying with auth credentials' if ENV['DEBUG']
          { response: 'ProvideCredentials' }.merge(@credentials || {})
        end

        async_command('Fetch.continueWithAuth', requestId: request_id, authChallengeResponse: credentials_response)
      end

      @session.on 'Runtime.consoleAPICalled' do |**params|
        # {"type"=>"log", "args"=>[{"type"=>"string", "value"=>"hello"}], "executionContextId"=>2, "timestamp"=>1548722854903.285, "stackTrace"=>{"callFrames"=>[{"functionName"=>"", "scriptId"=>"15", "url"=>"http://127.0.0.1:53977/", "lineNumber"=>6, "columnNumber"=>22}]}}
        details = params.dig(:stack_trace, 'callFrames')&.first
        @browser.console.log(params[:type],
                             params[:args].map { |arg| arg['description'] || arg['value'] }.join(' ').to_s,
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
      @session.on 'Runtime.exceptionThrown' do |exception_details: nil, **|
        @js_error ||= exception_details&.dig('exception', 'description') if @raise_js_errors

        details = exception_details&.dig('stackTrace', 'callFrames')&.first ||
                  exception_details || {}
        @browser.console.log('error',
                             exception_details&.dig('exception', 'description'),
                             source: details['url'].to_s.empty? ? nil : details['url'],
                             line_number: details['lineNumber'].to_i.zero? ? nil : details['lineNumber'],
                             columnNumber: details['columnNumber'].to_i.zero? ? nil : details['columnNumber'])
      end
    end

    def setup_network_blocking
      command 'Network.setBlockedURLs', urls: @url_blacklist
      setup_network_interception
    end

    def setup_network_interception
      async_command 'Network.setCacheDisabled', cacheDisabled: true
      async_command 'Fetch.enable', handleAuthRequests: true
    end

    def process_intercepted_fetch(interception_id, request, resource_type)
      navigation = (resource_type == 'Document')
      headers, url = request.values_at('headers', 'url')
      headers = headers.merge(extra_headers)

      unless @temp_headers.empty? || navigation # rubocop:disable Style/IfUnlessModifier
        headers.delete_if { |name, value| @temp_headers[name] == value }
      end
      unless @temp_no_redirect_headers.empty? || !navigation
        headers.delete_if { |name, value| @temp_no_redirect_headers[name] == value }
      end
      if (accept = perm_headers.keys.find { |k| /accept/i.match? k })
        headers[accept] = perm_headers[accept]
      end

      if @url_blacklist.any? { |r| url.match Regexp.escape(r).gsub('\*', '.*?') }
        async_command('Fetch.failRequest', errorReason: 'Failed', requestId: interception_id)
      elsif @url_whitelist.any?
        if @url_whitelist.any? { |r| url.match Regexp.escape(r).gsub('\*', '.*?') }
          async_command('Fetch.continueRequest',
                        requestId: interception_id,
                        headers: headers.map { |k, v| { name: k, value: v } })
        else
          async_command('Fetch.failRequest', errorReason: 'Failed', requestId: interception_id)
        end
      else
        async_command('Fetch.continueRequest',
                      requestId: interception_id,
                      headers: headers.map { |k, v| { name: k, value: v } })
      end
    end

    def go_history(delta)
      history = command('Page.getNavigationHistory')
      entry = history['entries'][history['currentIndex'] + delta]
      return nil unless entry

      main_frame.loading(-1)
      command('Page.navigateToHistoryEntry', entryId: entry['id'])
      wait_for_loaded
    end

    def accept_modal?(type, message:, manual:)
      if type == :beforeunload
        true
      else
        response = @modals.pop
        if !response&.key?(type)
          manual ? manual_unexpected_modal(type) : auto_unexpected_modal(type)
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
                         awaitPromise: true,
                         userGesture: true)
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

      exception = response['exceptionDetails']&.dig('exception')
      if exception
        case exception['className']
        when 'DOMException'
          raise ::Capybara::Apparition::BrowserError.new('name' => exception['description'], 'args' => nil)
        when 'ObsoleteException'
          raise ::Capybara::Apparition::ObsoleteNode.new(self, '') if exception['value'] == 'ObsoleteNode'
        else
          raise Capybara::Apparition::JavascriptError, [exception['description']]
        end
      end

      DevToolsProtocol::RemoteObject.new(self, response['result']).value
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

    def handle_proxy_auth(interception_id)
      credentials_response = if @proxy_auth_attempts.include?(interception_id)
        puts 'Cancelling proxy auth' if ENV['DEBUG']
        { response: 'CancelAuth' }
      else
        puts 'Replying with proxy auth credentials' if ENV['DEBUG']
        @proxy_auth_attempts.push(interception_id)
        { response: 'ProvideCredentials' }.merge(@browser.proxy_auth || {})
      end
      continue_request(interception_id, authChallengeResponse: credentials_response)
    end

    def handle_user_auth(interception_id)
      credentials_response = if @auth_attempts.include?(interception_id)
        puts 'Cancelling auth' if ENV['DEBUG']
        { response: 'CancelAuth' }
      else
        @auth_attempts.push(interception_id)
        puts 'Replying with auth credentials' if ENV['DEBUG']
        { response: 'ProvideCredentials' }.merge(@credentials || {})
      end
      continue_request(interception_id, authChallengeResponse: credentials_response)
    end

    EVALUATE_WITH_ID_JS = <<~JS
      function(){
        let apparitionId=0;
        return (function ider(obj){
          if (obj &&
              (typeof obj == 'object') &&
              !(obj instanceof HTMLElement) &&
              !(obj instanceof CSSStyleDeclaration) &&
              !obj.apparitionId){
            obj.apparitionId = ++apparitionId;
            Reflect.ownKeys(obj).forEach(key => ider(obj[key]))
          }
          return obj;
        })((function(){ return %<script>s }).apply(this, arguments))
      }
    JS

    EVALUATE_ASYNC_JS = <<~JS
      function(){
        var args = Array.prototype.slice.call(arguments);
        return new Promise((resolve, reject)=>{
          args.push(resolve);
          (function(){ %<script>s }).apply(this, args);
        });
      }
    JS

    EXECUTE_JS = <<~JS
      function(){
        %<script>s
      }
    JS

    CSS_FIND_JS = <<~JS
      Array.from(document.querySelectorAll("%<selector>s"));
    JS

    XPATH_FIND_JS = <<~JS
      (function(){
        const xpath = document.evaluate("%<selector>s", document, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
        let results = [];
        for (let i=0; i < xpath.snapshotLength; i++){
          results.push(xpath.snapshotItem(i))
        };
        return results;
      })()
    JS
  end
end
