require 'spec_helper'

module Capybara::Apparition
  describe 'Client' do
    skip "There is no Client anymore"

    let(:server) { double(port: 6000, host: "127.0.0.1") }
    let(:client_params) { {} }
    subject { Client.new(server, client_params) }

    xcontext '#initialize' do
      it 'shows the detected version in the version error message' do
        stub_version('1.3.0')
        expect { subject }.to raise_error(Cliver::Dependency::VersionMismatch) do |e|
          expect(e.message).to include('1.3.0')
        end
      end

      context 'when nodejs does not exist' do
        let(:client_params) { { path: '/does/not/exist' } }

        it 'raises an error' do
          expect { subject }.to raise_error(Cliver::Dependency::NotFound)
        end
      end

      def stub_version(version)
        allow_any_instance_of(Cliver::ShellCapture).to receive_messages(
          stdout: "#{version}\n",
          command_found: true
        )
      end
    end

    unless Capybara::Apparition.windows?
      it 'forcibly kills the child if it does not respond to SIGTERM' do
        client = Client.new(server)

        allow(Process).to receive_messages(spawn: 5678)
        allow(Process).to receive(:wait).and_return(nil)

        client.start

        expect(Process).to receive(:kill).with('TERM', 5678).ordered
        expect(Process).to receive(:kill).with('KILL', 5678).ordered

        client.stop
      end
    end
  end
end
