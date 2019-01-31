# frozen_string_literal: true

module Capybara::Apparition
  class Browser
    module Render
      def render(path, options = {})
        check_render_options!(options, path)
        img_data = current_page.render(options)
        File.open(path, 'wb') { |f| f.write(Base64.decode64(img_data)) }
      end

      def render_base64(options = {})
        check_render_options!(options)
        current_page.render(options)
      end

      attr_writer :zoom_factor

      def paper_size=(size)
        @paper_size = if size.is_a? Hash
          size
        else
          PAPER_SIZES.fetch(size) do
            raise_errors ArgumentError, "Unknwon paper size: #{size}"
          end
        end
      end

    private

      def check_render_options!(options, path = nil)
        options[:format] ||= File.extname(path).downcase[1..-1] if path
        options[:format] = :jpeg if options[:format].to_s == 'jpg'
        options[:full] = !!options[:full]
        return unless options[:full] && options.key?(:selector)

        warn "Ignoring :selector in #render since :full => true was given at #{caller(1..1)}"
        options.delete(:selector)
      end

      PAPER_SIZES = {
        'A3' => { width: 11.69, height: 16.53 },
        'A4' => { width: 8.27, height: 11.69 },
        'A5' => { width: 5.83, height: 8.27 },
        'Legal' => { width: 8.5, height: 14 },
        'Letter' => { width: 8.5, height: 11 },
        'Tabloid' => { width: 11, height: 17 },
        'Ledger' => { width: 17, height: 11 }
      }.freeze
    end
  end
end
