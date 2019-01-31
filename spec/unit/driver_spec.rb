# frozen_string_literal: true

require 'spec_helper'

module Capybara::Apparition
  describe Driver do
    let(:default_browser_options) { { 'remote-debugging-port' => 0 } }

    context 'with no options' do
      subject(:driver) { Driver.new(nil) }

      it 'does not log' do
        expect(driver.logger).to be_nil
      end

      it 'has no inspector' do
        expect(driver.inspector).to be_nil
      end

      it 'adds default browser options to driver options' do
        expect(driver.send(:browser_options)).to eq(default_browser_options)
      end
    end

    context 'with a browser_options option' do
      def driver_options(options)
        Driver.new(nil, browser_options: options).send(:browser_options)
      end

      it 'tales a hash' do
        expect(driver_options('hello' => nil, :other_setting => 3)).to include('hello' => nil, 'other-setting' => 3)
      end

      it 'takes an array' do
        expect(driver_options(['blah', 'my-option', :other_one])).to include('blah' => nil, 'my-option' => nil, 'other-one' => nil)
      end

      it 'takes an array including hashes' do
        expect(driver_options(['b', 'c', { d_e: 3, f: 4 }, 'g', { 'h' => 5 }])).to include(
          'b' => nil,
          'c' => nil,
          'd-e' => 3,
          'f' => 4,
          'g' => nil,
          'h' => 5
        )
      end

      it 'is a combination of default options and the provided options' do
        expect(driver_options(['hello'])).to eq('hello' => nil, 'remote-debugging-port' => 0)
      end
    end

    context 'with a :logger option' do
      subject(:driver) { Driver.new(nil, logger: :my_custom_logger) }

      it 'logs to the logger given' do
        expect(driver.logger).to eq(:my_custom_logger)
      end
    end

    context 'with a :browser_logger option' do
      subject(:driver) { Driver.new(nil, browser_logger: :my_custom_logger) }

      it 'logs to the browser_logger given' do
        expect(driver.browser_logger).to eq(:my_custom_logger)
      end
    end

    context 'with a :debug option' do
      subject(:driver) { Driver.new(nil, debug: true) }

      it 'logs to STDERR' do
        expect(driver.logger).to eq(STDERR)
      end
    end

    context 'with an :inspector option' do
      subject(:driver) { Driver.new(nil, inspector: 'foo') }

      it 'has an inspector' do
        expect(driver.inspector).not_to be_nil
        expect(driver.inspector).to be_a(Inspector)
        expect(driver.inspector.browser).to eq('foo')
      end

      it 'can pause indefinitely' do
        expect do
          Timeout.timeout(3) do
            driver.pause
          end
        end.to raise_error(Timeout::Error)
      end

      it 'can pause and resume with keyboard input' do
        IO.pipe do |read_io, write_io|
          stub_const('STDIN', read_io)
          write_io.write "\n"

          begin
            Timeout.timeout(3) do
              driver.pause
            end
          ensure
            write_io.close # without manual close JRuby 9.1.7.0 hangs here
          end
        end
      end

      it 'can pause and resume with signal' do
        Thread.new do
          sleep(2)
          Process.kill('CONT', Process.pid)
        end
        Timeout.timeout(4) do
          driver.pause
        end
      end
    end

    context 'with a :timeout option' do
      subject(:driver) { Driver.new(nil, timeout: 3) }

      it 'starts the server with the provided timeout', :fails do
        pending 'Implement this'
        server = double
        expect(Server).to receive(:new).with(anything, 3, nil).and_return(server)
        expect(driver.server).to eq(server)
      end
    end

    context 'with a :window_size option' do
      subject(:driver) { Driver.new(nil, window_size: [800, 600]) }

      it 'creates a client with the desired width and height settings', :fails do
        pending 'Need to update/remove this test'
        server = double
        expect(Server).to receive(:new).and_return(server)
        expect(Client).to receive(:start).with(server, hash_including(window_size: [800, 600]))

        driver.client
      end
    end
  end
end
