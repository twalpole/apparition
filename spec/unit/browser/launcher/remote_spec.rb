# frozen_string_literal: true

require 'spec_helper'

module Capybara::Apparition
  describe Browser::Launcher::Remote do
    subject(:launcher) { described_class.start(options) }

    let(:port) { rand(9000..10000) }
    let(:host) { '127.0.0.1' }
    let(:options) { { 'remote-debugging-address' => host, 'remote-debugging-port' => port } }

    context 'when browser available' do
      let(:local_launcher) { Browser::Launcher::Local.start(headless: true, browser_options: options) }

      before { local_launcher.ws_url }

      after { local_launcher.stop }

      it 'starts without error' do
        expect { launcher }.not_to raise_error
      end

      it 'returns ws_url' do
        expect(launcher.ws_url.to_s).to start_with("ws://#{host}:#{port}/")
      end
    end

    context 'when browser not started' do
      it 'fails with error' do
        error = "Cannot connect to remote Chrome at: 'http://#{host}:#{port}/json/version'"
        expect { launcher }.to raise_error(ArgumentError, error)
      end
    end
  end
end
