# frozen_string_literal: true

module Capybara::Apparition
  module DevToolsProtocol
    class RemoteObject
      attr_reader :params

      def initialize(page, params)
        @params = params
        @page = page
      end

      def value
        cyclic_checked_value({})
      end

    protected

      def cyclic_checked_value(object_cache)
        if object?
          if array?
            extract_properties_array(get_remote_object(object_id), object_cache)
          elsif node?
            params
          elsif object_class?
            extract_properties_object(get_remote_object(object_id), object_cache)
          elsif window_class?
            { object_id: object_id }
          else
            params['value']
          end
        else
          params['value']
        end
      end

    private

      def object?; type == 'object' end
      def array?; subtype == 'array' end
      def node?; subtype == 'node' end
      def object_class?; classname == 'Object' end
      def window_class?; classname == 'Window' end

      def type; params['type'] end
      def subtype; params['subtype'] end
      def object_id; params['objectId'] end
      def classname; params['className'] end

      def extract_properties_array(properties, object_cache)
        properties.reject { |prop| prop['name'] == 'apparitionId' }
                  .each_with_object([]) do |property, ary|
          # TODO: We may need to release these objects
          next unless property['enumerable']

          if property.dig('value', 'subtype') == 'node' # performance shortcut
            ary.push(property['value'])
          else
            ary.push(RemoteObject.new(@page, property['value']).cyclic_checked_value(object_cache))
          end
        end
      end

      def extract_properties_object(properties, object_cache)
        apparition_id = properties&.find { |prop| prop['name'] == 'apparitionId' }
                                  &.dig('value', 'value')

        result = if apparition_id
          return '(cyclic structure)' if object_cache.key?(apparition_id)

          object_cache[apparition_id] = {}
        end

        properties.reject { |prop| prop['name'] == 'apparitionId' }
                  .each_with_object(result || {}) do |property, hsh|
          # TODO: We may need to release these objects
          next unless property['enumerable']

          hsh[property['name']] = RemoteObject.new(@page, property['value']).cyclic_checked_value(object_cache)
        end
      end

      def get_remote_object(id)
        @page.command('Runtime.getProperties', objectId: id, ownProperties: true)['result']
      end
    end
  end
end
