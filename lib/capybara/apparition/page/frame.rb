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
      @loader_id = @prev_loader_id = nil
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

    def loader_id
      @frame_mutex.synchronize do
        @loader_id
      end
    end

    def loading(id)
      puts "Setting loading to #{id}" if ENV['DEBUG']
      self.loader_id = id
    end

    def reloading!
      puts 'Reloading' if ENV['DEBUG']
      self.loader_id = @prev_loader_id
    end

    def loading?
      !@loader_id.nil?
    end

    def loaded?
      @loader_id.nil?
    end

    def loaded!
      @prev_loader_id = loader_id
      puts "Setting loaded - was #{loader_id}" if ENV['DEBUG']
      self.loader_id = nil
    end

    def obsolete!
      self.state = :obsolete
    end

    def obsolete?
      state == :obsolete
    end

    def usable?
      context_id && !loading?
    end

  private

    def loader_id=(id)
      @frame_mutex.synchronize do
        @loader_id = id
      end
    end
  end
end
