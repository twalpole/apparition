# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

module Capybara::Apparition
  describe Browser do
    let(:server) { double('server').as_null_object }
    let(:client) { double('client').as_null_object }

    context 'with a logger' do
      subject(:browser) { Browser.new(server, client, logger) }

      let(:logger) { StringIO.new }

      it 'logs requests and responses to the client' do
        pending "Need to implement logging"
        response = %({"response":"<3"})
        allow(server).to receive(:send).and_return(response)

        browser.command('where is', 'the love?')

        expect(logger.string).to include('"name":"where is","args":["the love?"]')
        expect(logger.string).to include(response.to_s)
      end
    end
  end
end
