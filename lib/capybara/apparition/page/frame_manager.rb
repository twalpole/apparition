# frozen_string_literal: true

require 'capybara/apparition/page/frame'

module Capybara::Apparition
  class FrameManager
    def initialize(id)
      @frames = {}
      @frames_mutex = Mutex.new
      add(id).loading(-1)
      @main_id = @current_id = id
    end

    def main
      get(@main_id)
    end

    def current
      get(@current_id)
    end

    def pop_frame(top:)
      @current_id = if top
        @main_id
      else
        get(@current_id).parent_id
      end
      cleanup_unused_obsolete
    end

    def push_frame(id)
      @current_id = id
    end

    def add(id, frame_params = {})
      @frames_mutex.synchronize do
        @frames[id] = Frame.new(nil, frame_params.merge(frameId: id))
      end
    end

    def get(id)
      @frames_mutex.synchronize do
        @frames[id]
      end
    end

    def delete(id)
      @frames_mutex.synchronize do
        if @current_id == id
          @frames[id].obsolete!
        else
          @frames.delete(id)
        end
      end
    end

    def exists?(id)
      @frames_mutex.synchronize do
        @frames.key?(id)
      end
    end

    def destroy_context(ctx_id)
      @frames_mutex.synchronize do
        @frames.each_value do |f|
          f.context_id = nil if f.context_id == ctx_id
        end
      end
    end

  private

    def cleanup_unused_obsolete
      @frames_mutex.synchronize do
        @frames.delete_if do |_id, f|
          f.obsolete? && (f.id != @current_id)
        end
      end
    end
  end
end
