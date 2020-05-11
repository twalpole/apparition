# frozen_string_literal: true

require 'spec_helper'

module Capybara::Apparition
  describe Browser::Launcher do
    let(:local_launcher) { instance_double(described_class::Local) }
    let(:remote_launcher) { instance_double(described_class::Remote) }
    let(:browser_options) { { test: true } }

    before do
      allow(described_class::Local).to receive(:start).and_return(local_launcher)
      allow(described_class::Remote).to receive(:start).and_return(remote_launcher)
    end

    context 'when {remote: true}' do
      let(:options) { { remote: true, browser_options: browser_options } }

      it 'returns remote launcher' do
        expect(described_class.start(options)).to eq(remote_launcher)
      end

      it 'passing correct options' do
        described_class.start(options)

        expect(described_class::Remote).to have_received(:start).with(browser_options)
      end
    end

    context 'when {remote: false}' do
      let(:options) { { remote: false, headless: false, browser_options: browser_options } }

      it 'returns local launcher' do
        expect(described_class.start(options)).to eq(local_launcher)
      end

      it 'passing correct options' do
        described_class.start(options)

        expect(described_class::Local).to have_received(:start).with(headless: false, browser_options: browser_options)
      end
    end

    context 'when {remote: nil}' do
      let(:options) { { remote: nil, headless: true, browser_options: browser_options } }

      it 'returns local launcher' do
        expect(described_class.start(options)).to eq(local_launcher)
      end

      it 'passing correct options' do
        described_class.start(options)

        expect(described_class::Local).to have_received(:start).with(headless: true, browser_options: browser_options)
      end
    end
  end
end
