# frozen_string_literal: true

require 'net/http'

module Capybara::Apparition
  class CDP
    extend Forwardable

    def self.generate(ws_url)

      uri = URI("http://#{Addressable::URI.parse(ws_url.to_s).authority}/json/protocol")
      json = JSON.parse(Net::HTTP.get(uri))

      # client =
      cdp = self.new(::Capybara::Apparition::ChromeClient.client(ws_url.to_s))

      json["domains"].each do |domain|
        domain_name = domain["domain"]

        cdp.singleton_class.class_eval <<~CLASS, __FILE__, __LINE__ + 1
          class #{domain_name}
            def initialize(client)
              @client = client
            end
          end
        CLASS

        Array(domain["commands"]).each do |cmd|
          method_name = cmd["name"].gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
          method_params = Array(cmd["parameters"]).each_with_object(['_session_id: nil']) do |param, arr|
            arr << "#{param["name"].gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase}: #{param["optional"] ? 'nil' : ''}"
          end.join(', ')

          cdp.singleton_class.class_eval <<~DOMAIN, __FILE__, __LINE__ + 1
            class #{domain_name}
              def #{method_name}(#{method_params})
                #{"warn('#{domain_name}::#{method_name} is deprecated')" if domain["deprecated"]}
                _params = method(__method__).parameters.each_with_object({}) do |param, hsh|
                  _type, _name = param
                  _camel = _name.to_s.gsub(/(_[a-z])/){ |match| match[1].upcase }
                  _value = eval(_name.to_s)
                  hsh[_camel] = _value unless _type==:key && _value.nil?
                end
                _session_id = _params.delete('SessionId')
                if _session_id
                  @client.send_cmd_to_session(_session_id, '#{domain_name}.#{cmd['name']}', _params)
                else
                  @client.send_cmd('#{domain_name}.#{cmd['name']}', _params)
                end
              end
            end
          DOMAIN
        end

        Array(domain["events"]).each do |event|
          method_name = "on_#{event["name"].gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase}"
          cdp.singleton_class.class_eval <<~EVENT_HANDLING, __FILE__, __LINE__ + 1
            class #{domain_name}
              def #{method_name}(session_id: nil, &block)
                @client.on('#{domain_name}.#{event['name']}', session_id, &block)
              end
            end
          EVENT_HANDLING
        end

        domain_accessor = domain_name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase

        cdp.define_singleton_method(domain_accessor) do
          @domains[domain_accessor] ||= singleton_class.const_get(domain_name).new(@client)
        end
      end
      cdp
    end

    def initialize(client)
      @domains = {}
      @client = client
    end

    delegate [:stop, :timeout, :timeout=] => :@client

  private

    def snakeize(camel)
      camel.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end

    attr_reader :client

  end
end
