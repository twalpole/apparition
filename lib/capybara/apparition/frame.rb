module Capybara::Apparition
  class Frame

    attr_reader :id, :context_id, :parent_id
    attr_accessor :state, :element_id

    def initialize(page, params)
      @page = page
      @id = params[:frameId] || params["frameId"] || params["id"]
      @parent_id = params["parentFrameId"] || params["parentId"]
      @context_id = nil
      @state = nil
      @element_id = nil
    end

    def context_id=(id)
      @context_id = id
    end

    def loading?
      state == :loading
    end
  end
end