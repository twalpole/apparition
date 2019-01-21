# frozen_string_literal: true

module Capybara::Apparition
  class Browser
    class Launcher
      KILL_TIMEOUT = 2

      BROWSER_HOST = '127.0.0.1'
      BROWSER_PORT = '0'

      # Chromium command line options
      # https://peter.sh/experiments/chromium-command-line-switches/
      DEFAULT_OPTIONS = {
        'disable-background-networking' => nil,
        'disable-background-timer-throttling' => nil,
        'disable-breakpad' => nil,
        'disable-client-side-phishing-detection' => nil,
        'disable-default-apps' => nil,
        'disable-dev-shm-usage' => nil,
        'disable-extensions' => nil,
        'disable-features=site-per-process' => nil,
        'disable-hang-monitor' => nil,
        'disable-popup-blocking' => nil,
        'disable-prompt-on-repost' => nil,
        'disable-sync' => nil,
        'disable-translate' => nil,
        'metrics-recording-only' => nil,
        'no-first-run' => nil,
        'safebrowsing-disable-auto-update' => nil,
        'enable-automation' => nil,
        'password-store=basic' => nil,
        'use-mock-keychain' => nil,
        'keep-alive-for-test' => nil,
        # headless options
        'headless' => nil,
        'hide-scrollbars' => nil,
        'mute-audio' => nil,

        # really only needed on windows
        'disable-gpu' => nil,

        'window-size' => '1024,768',
        'homepage' => 'about:blank',
        # Note: --no-sandbox is not needed if you properly setup a user in the container.
        # https://github.com/ebidel/lighthouse-ci/blob/master/builder/Dockerfile#L35-L40
        # "no-sandbox" => nil,
        # "disable-web-security" => nil,
        'remote-debugging-port' => BROWSER_PORT,
        'remote-debugging-address' => BROWSER_HOST
      }.freeze

      def self.start(*args)
        new(*args).tap(&:start)
      end

      def self.process_killer(pid)
        proc do
          begin
            if Capybara::Apparition.windows?
              ::Process.kill('KILL', pid)
            else
              ::Process.kill('TERM', pid)
              start = Time.now
              while ::Process.wait(pid, ::Process::WNOHANG).nil?
                sleep 0.05
                next unless (Time.now - start) > KILL_TIMEOUT

                ::Process.kill('KILL', pid)
                ::Process.wait(pid)
                break
              end
            end
          rescue Errno::ESRCH, Errno::ECHILD
          end
        end
      end

      def initialize(**options)
        @path = ENV['BROWSER_PATH']
        @options = DEFAULT_OPTIONS.merge(options.fetch(:browser, {}))
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

        sleep 3
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
                    find_first_binary('google-chrome', 'chrome') || '/usr/bin/chrome'
                  else
                    raise ArgumentError, "unknown os: #{host_os.inspect}"
                  end

        raise ArgumentError, 'Unable to find Chrome executeable' unless File.file?(@path.to_s) && File.executable?(@path.to_s)

        @path
      end

      def windows_path
        raise ArgumentError, 'Not yet Implemented'
      end

      def macosx_path
        path = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
        path = File.expand_path('~/Applications/Google Chrome.app/Contents/MacOS/Google Chrome') unless File.exist?(path)
        path = find_first_binary('Google Chrome') unless File.exist?(path)
        path
      end

      def find_first_binary(*binaries)
        paths = ENV['PATH'].split(File::PATH_SEPARATOR)

        binaries.each do |binary|
          paths.each do |path|
            full_path = File.join(path, binary)
            exe = Dir.glob(full_path).find { |f| File.executable?(f) }
            return exe if exe
          end
        end
      end
    end
  end
end
