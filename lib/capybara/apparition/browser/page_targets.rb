# frozen_string_literal: true

module Capybara::Apparition
  class Browser
    module PageTargets
      def current_page(allow_nil: false)
        @pages[@current_page_handle] || begin
          puts "No current page: #{@current_page_handle} : #{caller}" if ENV['DEBUG']
          @current_page_handle = nil
          raise NoSuchWindowError unless allow_nil

          @current_page_handle
        end
      end

    private

      def join_all_target_threads
        puts 'Joining target threads' if ENV['DEBUG']
        @target_threads.each(&:join).clear
        puts 'Target threads joined' if ENV['DEBUG']
      end

      def page_ids
        @pages.keys
      end

      def remove_page(id)
        @pages.delete(id)
      end

      def wait_for_page(id)
        sleep 0.05 until @pages[id]
      end

      def mark_page_loaded(id)
        @pages[id].send(:main_frame).loaded!
      end

      def each_page
        @pages.each do |_id, page|
          yield page
        end
      end

      def wait_for_usable_page(id, timeout: 10)
        timer = Capybara::Helpers.timer(expire_in: timeout)
        until @pages[id].usable?
          if timer.expired?
            puts 'Timedout waiting for reset'
            raise TimeoutError.new('reset')
          end
          sleep 0.01
        end
      end

      def initialize_target_handlers
        @client.on 'Target.targetCreated' do |info|
          ti = info['targetInfo']
          if ti['type'] == 'page'
            @target_threads.push(Thread.start do
              begin
                # @client.with_session_paused do
                new_target_id = ti['targetId']
                session_id = command('Target.attachToTarget', targetId: new_target_id)['sessionId']
                session = Capybara::Apparition::DevToolsProtocol::Session.new(self, client, session_id)
                new_page = Page.new(self, session, new_target_id, ti['browserContextId'],
                                    ignore_https_errors: ignore_https_errors,
                                    js_errors: js_errors, extensions: @extensions,
                                    url_blacklist: @url_blacklist, url_whitelist: @url_whitelist)
                new_page.inherit(@pages[ti['openerId']]) if ti['openerId']
                @pages[new_target_id] = new_page
                # end
                timer = Capybara::Helpers.timer(expire_in: 0.5)
                until !ti['openerId'] || new_page.usable?
                  # No way to currently guarantee we get all the messages so assume loaded if dynamically opened (popup)
                  # Driver waiting for page to be loaded is not a Capybara requirement
                  new_page.send(:main_frame).loaded! if timer.expired?
                end
              rescue => e # rubocop:disable Style/RescueStandardError
                puts e.message
              end
            end)
          end
        end

        @client.on 'Target.targetDestroyed' do |info|
          puts "**** Target Destroyed Info: #{info}" if ENV['DEBUG']
          @pages.delete(info['targetId'])
        end

        @client.on 'Target.targetInfoChanged' do |info|
          # ti = info['targetInfo']
        end
      end
    end
  end
end
