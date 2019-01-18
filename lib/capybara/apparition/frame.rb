# frozen_string_literal: true

module Capybara::Apparition
  class Frame
    attr_reader :id, :parent_id
    attr_accessor :element_id

    def initialize(page, params)
      @page = page
      @id = params[:frameId] || params['frameId'] || params['id']
      @parent_id = params['parentFrameId'] || params['parentId']
      @context_id = nil
      @state = nil
      @element_id = nil
      @frame_mutex = Mutex.new
    end

    def context_id
      @frame_mutex.synchronize do
        @context_id
      end
    end

    def context_id=(id)
      @frame_mutex.synchronize do
        @context_id = id
      end
    end

    def state=(state)
      @frame_mutex.synchronize do
        @state = state
      end
    end

    def state
      @frame_mutex.synchronize do
        @state
      end
    end

    def loading?
      state == :loading
    end

    def loaded?
      state == :loaded
    end

    def obsolete!
      self.state = :obsolete
    end

    def obsolete?
      self.state == :obsolete
    end

    def usable?
      context_id && !loading?
    end
  end
end
