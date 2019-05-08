# frozen_string_literal: true

module Capybara::Apparition
  class Browser
    class Launcher
      KILL_TIMEOUT = 5

      def self.start(*args)
        new(*args).tap(&:start)
      end

      def self.process_killer(pid)
        proc do
          begin
            sleep 1
            if Capybara::Apparition.windows?
              ::Process.kill('KILL', pid)
            else
              ::Process.kill('USR1', pid)
              timer = Capybara::Helpers.timer(expire_in: KILL_TIMEOUT)
              while ::Process.wait(pid, ::Process::WNOHANG).nil?
                sleep 0.05
                next unless timer.expired?

                ::Process.kill('KILL', pid)
                ::Process.wait(pid)
                break
              end
            end
          rescue Errno::ESRCH, Errno::ECHILD # rubocop:disable Lint/HandleExceptions
          end
        end
      end

      def initialize(headless:, **options)
        @path = ENV['BROWSER_PATH']
        @options = DEFAULT_OPTIONS.merge(options[:browser_options] || {})
        if headless
          @options.merge!(HEADLESS_OPTIONS)
          @options['disable-gpu'] = nil if Capybara::Apparition.windows?
        end
        @options['user-data-dir'] = Dir.mktmpdir
      end

      def start
        @output = Queue.new
        @read_io, @write_io = IO.pipe

        @out_thread = Thread.new do
          while !@read_io.eof? && (data = @read_io.readpartial(512))
            @output << data
          end
        end

        process_options = { in: File::NULL }
        process_options[:pgroup] = true unless Capybara::Apparition.windows?
        process_options[:out] = process_options[:err] = @write_io if Capybara::Apparition.mri?

        redirect_stdout do
          cmd = [path] + @options.map { |k, v| v.nil? ? "--#{k}" : "--#{k}=#{v}" }
          @pid = ::Process.spawn(*cmd, process_options)
          ObjectSpace.define_finalizer(self, self.class.process_killer(@pid))
        end
      end

      def stop
        return unless @pid

        kill
        ObjectSpace.undefine_finalizer(self)
      end

      def restart
        stop
        start
      end

      def host
        @host ||= ws_url.host
      end

      def port
        @port ||= ws_url.port
      end

      def ws_url
        @ws_url ||= begin
          regexp = %r{DevTools listening on (ws://.*)}
          url = nil
          loop do
            break if (url = @output.pop.scan(regexp)[0])
          end
          @out_thread.kill
          close_io
          Addressable::URI.parse(url[0])
        end
      end

    private

      def redirect_stdout
        if Capybara::Apparition.mri?
          yield
        else
          begin
            prev = STDOUT.dup
            $stdout = @write_io
            STDOUT.reopen(@write_io)
            yield
          ensure
            STDOUT.reopen(prev)
            $stdout = STDOUT
            prev.close
          end
        end
      end

      def kill
        self.class.process_killer(@pid).call
        @pid = nil
      end

      def close_io
        [@write_io, @read_io].each do |io|
          begin
            io.close unless io.closed?
          rescue IOError
            raise unless RUBY_ENGINE == 'jruby'
          end
        end
      end

      def path
        host_os = RbConfig::CONFIG['host_os']
        @path ||= case RbConfig::CONFIG['host_os']
        when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
          windows_path
        when /darwin|mac os/
          macosx_path
        when /linux|solaris|bsd/
          linux_path
        else
          raise ArgumentError, "unknown os: #{host_os.inspect}"
        end

        raise ArgumentError, 'Unable to find Chrome executeable' unless File.file?(@path.to_s) && File.executable?(@path.to_s)

        @path
      end

      def windows_path
        envs = %w[LOCALAPPDATA PROGRAMFILES PROGRAMFILES(X86)]
        directories = %w[\\Google\\Chrome\\Application \\Chromium\\Application]
        files = %w[chrome.exe]

        directories.product(envs, files).lazy.map { |(dir, env, file)| "#{ENV[env]}\\#{dir}\\#{file}" }
                   .find { |f| File.exist?(f) } || find_first_binary(*files)
      end

      def macosx_path
        directories = ['', File.expand_path('~')]
        files = ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
                 '/Applications/Chromium.app/Contents/MacOS/Chromium']
        directories.product(files).map(&:join).find { |f| File.exist?(f) } ||
          find_first_binary('Google Chrome', 'Chromium')
      end

      def linux_path
        directories = %w[/usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin /opt/google/chrome]
        files = %w[google-chrome chrome chromium chromium-browser]

        directories.product(files).map { |p| p.join('/') }.find { |f| File.exist?(f) } ||
          find_first_binary(*files)
      end

      def find_first_binary(*binaries)
        paths = ENV['PATH'].split(File::PATH_SEPARATOR)

        binaries.product(paths).lazy.map do |(binary, path)|
          Dir.glob(File.join(path, binary)).find { |f| File.executable?(f) }
        end.reject(&:nil?).first
      end

      # Chromium command line options
      # https://peter.sh/experiments/chromium-command-line-switches/
      DEFAULT_BOOLEAN_OPTIONS = %w[
        disable-background-networking
        disable-background-timer-throttling
        disable-breakpad
        disable-client-side-phishing-detection
        disable-default-apps
        disable-dev-shm-usage
        disable-extensions
        disable-features=site-per-process
        disable-hang-monitor
        disable-infobars
        disable-popup-blocking
        disable-prompt-on-repost
        disable-sync
        disable-translate
        disable-session-crashed-bubble
        metrics-recording-only
        no-first-run
        safebrowsing-disable-auto-update
        enable-automation
        password-store=basic
        use-mock-keychain
        keep-alive-for-test
      ].freeze
      # Note: --no-sandbox is not needed if you properly setup a user in the container.
      # https://github.com/ebidel/lighthouse-ci/blob/master/builder/Dockerfile#L35-L40
      # no-sandbox
      # disable-web-security
      DEFAULT_VALUE_OPTIONS = {
        'window-size' => '1024,768',
        'homepage' => 'about:blank',
        'remote-debugging-address' => '127.0.0.1'
      }.freeze
      DEFAULT_OPTIONS = DEFAULT_BOOLEAN_OPTIONS.each_with_object({}) { |opt, hsh| hsh[opt] = nil }
                                               .merge(DEFAULT_VALUE_OPTIONS)
                                               .freeze
      HEADLESS_OPTIONS = {
        'headless' => nil,
        'hide-scrollbars' => nil,
        'mute-audio' => nil
      }.freeze
    end
  end
end
