module Minitest
  module Dispatch
    module Connection
      class Manager
        include CallbacksMixin

        def initialize(consumers:, timeout: Settings::DEFAULT_TIMEOUT)
          @consumers = consumers.split(",")
          @adapters = {}
          @timeout = timeout
        end

        def open_all
          @consumers.each do |consumer|
            host, port = consumer.split(":")
            adapter = Adapter.new(
              host: host,
              port: port,
              timeout: @timeout
            )
            adapter.connect
            adapter.connection.add_callback(:receive_object) do |object|
              trigger_callback(:receive_object, object)
            end
            adapter.connection.add_callback(:unbind) do |object|
              trigger_callback(:unbind, object)
            end
            @adapters[adapter.connection_id] = adapter
          end
        end

        def next_connection
          @adapters.values.first.connection
        end

        def adapter_for(connection_id:)
          @adapters[connection_id]
        end

        def open_connections?
          @adapters.values.any? { |adapter| !adapter.connection.nil? }
        end

        def close_all
          @adapters.each_value do |adapter|
            adapter.connection.close_connection_after_writing unless adapter.connection.nil?
          end
        end
      end
    end
  end
end
