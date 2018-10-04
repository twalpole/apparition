# frozen_string_literal: true

module Capybara::Apparition
  class Frame
    attr_reader :id, :context_id, :parent_id
    attr_accessor :state, :element_id

    def initialize(page, params)
      @page = page
      @id = params[:frameId] || params['frameId'] || params['id']
      @parent_id = params['parentFrameId'] || params['parentId']
      @context_id = nil
      @state = nil
      @element_id = nil
    end

    attr_writer :context_id

    def loading?
      state == :loading
    end
  end
end
