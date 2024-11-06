module Minitest
  module Dispatch
    module Connection
      # This will manage a collection of addapters (consumer connections)
      class Manager
        include CallbacksMixin

        def initialize(consumers:, timeout: nil)
          @consumers = consumers.split(",")
          @adapters = {}
          @timeout = timeout || Settings::DEFAULT_TIMEOUT
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
          @adapters.values.any?(&:connected?)
        end

        def disconnected?
          !open_connections?
        end

        def reconnect
          @adapters.each_value do |adapter|
            !adapter.connected? && !adapter.reconnect
          end
        end

        def close_all
          @adapters.each_value do |adapter|
            unless adapter.connection.nil?
              adapter.connection.send_object({ action: :disconnect })
              adapter.connection.close_connection_after_writing
            end
          end
        end
      end
    end
  end
end
