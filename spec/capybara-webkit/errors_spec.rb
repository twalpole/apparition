# frozen_string_literal: true

require 'spec_helper'

describe 'Capybara::Apparition::JsonError', :skip do
  subject { error.exception }

  let(:error) { described_class.new '{"class": "ClickFailed", "message": "Error clicking this element"}' }

  it { is_expected.to be_an_instance_of Capybara::Apparition::ClickFailed }

  it { expect(subject.message).to eq 'Error clicking this element' }
end
